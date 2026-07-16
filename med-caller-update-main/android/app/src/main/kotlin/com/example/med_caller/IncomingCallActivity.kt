package com.example.med_caller

import android.app.Activity
import android.app.AlertDialog
import android.app.KeyguardManager
import android.content.Context
import android.content.Intent
import android.database.Cursor
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.drawable.ColorDrawable
import android.graphics.drawable.GradientDrawable
import android.media.AudioManager
import android.media.MediaRecorder
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.os.PowerManager
import android.provider.ContactsContract
import android.util.Log
import android.view.View
import android.view.WindowManager
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FirebaseFirestore
import java.io.InputStream
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class IncomingCallActivity : Activity() {

    companion object {
        private const val TAG = "IncomingCallActivity"
        const val EXTRA_NUMBER = "call_number"
        const val EXTRA_CALLER_NAME = "caller_name"
        const val EXTRA_CALL_STATE = "call_state"

        var instance: IncomingCallActivity? = null
    }

    private var wakeLock: PowerManager.WakeLock? = null
    private val db = FirebaseFirestore.getInstance()

    private var isMuted = false
    private var isSpeakerOn = false
    private var isRecording = false
    private var mediaRecorder: MediaRecorder? = null
    private var audioManager: AudioManager? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        instance = this

        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(
            PowerManager.SCREEN_BRIGHT_WAKE_LOCK or PowerManager.ACQUIRE_CAUSES_WAKEUP,
            "MedCaller:IncomingCallWakeLock"
        )
        wakeLock?.acquire(10000)

        window.addFlags(
            WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
            WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
            WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
        )

        val km = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
            km.requestDismissKeyguard(this, null)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD)
        }

        setContentView(R.layout.activity_incoming_call)

        audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager

        val number = intent.getStringExtra(EXTRA_NUMBER) ?: ""
        val callerName = intent.getStringExtra(EXTRA_CALLER_NAME) ?: ""
        val callState = intent.getStringExtra(EXTRA_CALL_STATE) ?: "RINGING"

        val avatar = findViewById<ImageView>(R.id.avatar)
        val nameText = findViewById<TextView>(R.id.callerName)
        val numberText = findViewById<TextView>(R.id.callerNumber)

        nameText.text = callerName.ifEmpty { "Unknown Caller" }
        numberText.text = if (number.isNotEmpty()) "+91 $number" else ""

        loadContactPhoto(number, avatar, callerName)

        // ── Answer / Decline ──────────────────────────────────────────────────
        findViewById<LinearLayout>(R.id.rejectBtn).setOnClickListener {
            Log.d(TAG, "Reject clicked")
            CallStateManager.rejectCall()
            finish()
        }

        findViewById<LinearLayout>(R.id.answerBtn).setOnClickListener {
            Log.d(TAG, "Answer clicked")
            CallStateManager.answerCall()
        }

        // ── Mute ──────────────────────────────────────────────────────────────
        findViewById<LinearLayout>(R.id.muteBtn).setOnClickListener {
            isMuted = !isMuted
            CallStateManager.muteCall(isMuted)
            val icon = findViewById<ImageView>(R.id.muteIcon)
            val label = findViewById<TextView>(R.id.muteLabel)
            if (isMuted) {
                icon.background = getActiveBtnBg()
                label.setTextColor(0xFF2962FF.toInt())
                label.text = "Unmute"
                Toast.makeText(this, "Microphone muted", Toast.LENGTH_SHORT).show()
            } else {
                icon.background = getInactiveBtnBg()
                label.setTextColor(0xFF888888.toInt())
                label.text = "Mute"
                Toast.makeText(this, "Microphone on", Toast.LENGTH_SHORT).show()
            }
        }

        // ── Keypad ────────────────────────────────────────────────────────────
        findViewById<LinearLayout>(R.id.keypadBtn).setOnClickListener {
            showDtmfKeypad()
        }

        // ── Speaker ───────────────────────────────────────────────────────────
        findViewById<LinearLayout>(R.id.speakerBtn).setOnClickListener {
            isSpeakerOn = !isSpeakerOn
            CallStateManager.toggleSpeaker(isSpeakerOn)
            val icon = findViewById<ImageView>(R.id.speakerIcon)
            val label = findViewById<TextView>(R.id.speakerLabel)
            if (isSpeakerOn) {
                icon.background = getActiveBtnBg()
                label.setTextColor(0xFF2962FF.toInt())
                Toast.makeText(this, "Speaker on", Toast.LENGTH_SHORT).show()
            } else {
                icon.background = getInactiveBtnBg()
                label.setTextColor(0xFF888888.toInt())
                Toast.makeText(this, "Speaker off", Toast.LENGTH_SHORT).show()
            }
        }

        // ── Record ────────────────────────────────────────────────────────────
        findViewById<LinearLayout>(R.id.recordBtn).setOnClickListener {
            toggleRecording()
        }

        // ── Add New Patient ───────────────────────────────────────────────────
        findViewById<LinearLayout>(R.id.addPatientBtn).setOnClickListener {
            Toast.makeText(this, "Opening patient form...", Toast.LENGTH_SHORT).show()
            try {
                val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
                if (launchIntent != null) {
                    launchIntent.putExtra("navigate_to", "add_patient")
                    launchIntent.putExtra("patient_phone", number)
                    launchIntent.addFlags(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
                    startActivity(launchIntent)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to launch add patient: ${e.message}")
            }
        }

        // ── Video Call ────────────────────────────────────────────────────────
        findViewById<LinearLayout>(R.id.videoCallBtn).setOnClickListener {
            Toast.makeText(this, "Video call feature coming soon", Toast.LENGTH_SHORT).show()
        }

        // ── Fetch patient data ────────────────────────────────────────────────
        fetchPatientData(number)

        Log.d(TAG, "Showing incoming call: $callerName ($number)")
    }

    // ── DTMF Keypad ────────────────────────────────────────────────────────────

    private fun showDtmfKeypad() {
        val dialogView = layoutInflater.inflate(R.layout.layout_dtmf_keypad, null)
        val dialog = AlertDialog.Builder(this)
            .setView(dialogView)
            .create()

        dialog.window?.setBackgroundDrawable(ColorDrawable(android.graphics.Color.TRANSPARENT))

        val keys = mapOf(
            R.id.key1 to '1', R.id.key2 to '2', R.id.key3 to '3',
            R.id.key4 to '4', R.id.key5 to '5', R.id.key6 to '6',
            R.id.key7 to '7', R.id.key8 to '8', R.id.key9 to '9',
            R.id.keyStar to '*', R.id.key0 to '0', R.id.keyHash to '#'
        )

        for ((id, digit) in keys) {
            dialogView.findViewById<TextView>(id).setOnClickListener {
                CallStateManager.playDtmf(digit)
                it.alpha = 0.5f
                it.postDelayed({ it.alpha = 1.0f }, 100)
            }
        }

        dialog.show()
    }

    // ── Recording ───────────────────────────────────────────────────────────────

    @Suppress("DEPRECATION")
    private fun toggleRecording() {
        val icon = findViewById<ImageView>(R.id.recordIcon)
        val label = findViewById<TextView>(R.id.recordLabel)

        if (!isRecording) {
            try {
                val dir = getExternalFilesDir(Environment.DIRECTORY_RECORDINGS)
                val fileName = "CALL_${SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(Date())}.mp4"
                val filePath = "$dir/$fileName"

                mediaRecorder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    MediaRecorder(this)
                } else {
                    @Suppress("DEPRECATION")
                    MediaRecorder()
                }

                mediaRecorder?.apply {
                    setAudioSource(MediaRecorder.AudioSource.VOICE_COMMUNICATION)
                    setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
                    setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
                    setAudioSamplingRate(44100)
                    setAudioEncodingBitRate(128000)
                    setOutputFile(filePath)
                    prepare()
                    start()
                }

                isRecording = true
                icon.background = getRecordingBg()
                label.setTextColor(0xFFE53935.toInt())
                label.text = "Recording"
                Toast.makeText(this, "Recording started", Toast.LENGTH_SHORT).show()
                Log.d(TAG, "Recording started: $filePath")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to start recording: ${e.message}", e)
                Toast.makeText(this, "Recording failed", Toast.LENGTH_SHORT).show()
            }
        } else {
            try {
                mediaRecorder?.apply {
                    stop()
                    release()
                }
                mediaRecorder = null
                isRecording = false
                icon.background = getInactiveBtnBg()
                label.setTextColor(0xFF888888.toInt())
                label.text = "Record"
                Toast.makeText(this, "Recording saved", Toast.LENGTH_SHORT).show()
            } catch (e: Exception) {
                Log.e(TAG, "Failed to stop recording: ${e.message}", e)
                mediaRecorder = null
                isRecording = false
                icon.background = getInactiveBtnBg()
                label.setTextColor(0xFF888888.toInt())
                label.text = "Record"
            }
        }
    }

    // ── Button background helpers ───────────────────────────────────────────────

    private fun getActiveBtnBg(): GradientDrawable {
        return GradientDrawable().apply {
            shape = GradientDrawable.OVAL
            setColor(0xFFE3F2FD.toInt())
        }
    }

    private fun getInactiveBtnBg(): GradientDrawable {
        return GradientDrawable().apply {
            shape = GradientDrawable.OVAL
            setColor(0xFFF0F0F0.toInt())
        }
    }

    private fun getRecordingBg(): GradientDrawable {
        return GradientDrawable().apply {
            shape = GradientDrawable.OVAL
            setColor(0xFFFFEBEE.toInt())
        }
    }

    // ── Call active state ───────────────────────────────────────────────────────

    fun onCallActive() {
        runOnUiThread {
            findViewById<TextView>(R.id.incomingLabel)?.text = "CLINICAL CALL ACTIVE"
            findViewById<LinearLayout>(R.id.rejectBtn)?.visibility = View.GONE
            findViewById<LinearLayout>(R.id.answerBtn)?.visibility = View.GONE
        }
    }

    // ── Firestore: fetch patient by phone number ──────────────────────────────

    private fun fetchPatientData(phoneNumber: String) {
        if (phoneNumber.isEmpty()) return

        val doctorId = getDoctorId()
        if (doctorId.isEmpty()) {
            Log.w(TAG, "No doctor ID — cannot fetch patient")
            return
        }

        Log.d(TAG, "Fetching patient for phone: $phoneNumber (doctor: $doctorId)")

        db.collection("users").document(doctorId)
            .collection("patients").document(phoneNumber)
            .get()
            .addOnSuccessListener { doc ->
                if (doc.exists()) {
                    val data = doc.data
                    if (data != null) {
                        runOnUiThread { populateClinicalContext(data) }
                        Log.d(TAG, "Patient data loaded: ${data["name"]}")
                    }
                } else {
                    Log.d(TAG, "Patient not found for $phoneNumber")
                    runOnUiThread { showNoPatientState() }
                }
            }
            .addOnFailureListener { e ->
                Log.e(TAG, "Failed to fetch patient: ${e.message}", e)
            }
    }

    private fun getDoctorId(): String {
        val user = FirebaseAuth.getInstance().currentUser
        if (user != null && !user.phoneNumber.isNullOrEmpty()) {
            return user.phoneNumber!!
        }
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        return prefs.getString("flutter.loggedInPhone", "") ?: ""
    }

    private fun populateClinicalContext(data: Map<String, Any>) {
        val chiefComplaint = data["issue"] as? String
            ?: data["healthIssue"] as? String
            ?: ""
        val medication = data["medication"] as? String ?: ""
        val notes = data["notes"] as? String ?: ""
        val symptoms = data["symptoms"] as? String ?: ""
        val status = data["status"] as? String ?: "improving"
        val allergies = data["allergies"] as? String ?: ""

        findViewById<TextView>(R.id.chiefComplaint).text = chiefComplaint.ifEmpty { "—" }
        findViewById<TextView>(R.id.medication).text = medication.ifEmpty { "—" }

        val previousIssues = buildString {
            if (symptoms.isNotEmpty()) append(symptoms)
            if (notes.isNotEmpty()) {
                if (isNotEmpty()) append("\n")
                append(notes)
            }
            if (allergies.isNotEmpty() && allergies != "None") {
                if (isNotEmpty()) append("\n")
                append("Allergies: $allergies")
            }
        }
        findViewById<TextView>(R.id.previousIssues).text = previousIssues.ifEmpty { "—" }

        val (label, color) = when (status) {
            "recovering" -> "Recovering" to 0xFF4CAF50.toInt()
            "improving" -> "Improving" to 0xFFFFA726.toInt()
            "no_improvement" -> "No Improvement" to 0xFFE53935.toInt()
            else -> "Improving" to 0xFFFFA726.toInt()
        }

        findViewById<TextView>(R.id.statusText).text = label
        (findViewById<View>(R.id.statusDot).background as? GradientDrawable)?.setColor(color)
    }

    private fun showNoPatientState() {
        findViewById<TextView>(R.id.chiefComplaint)?.text = "—"
        findViewById<TextView>(R.id.medication)?.text = "—"
        findViewById<TextView>(R.id.previousIssues)?.text = "—"
        findViewById<TextView>(R.id.statusText)?.text = "Unknown"
    }

    // ── Contact photo loading ─────────────────────────────────────────────────

    private fun loadContactPhoto(number: String, avatar: ImageView, callerName: String) {
        if (number.isEmpty()) return
        val photo = queryContactPhotoByNumber(number)
        if (photo != null) {
            avatar.setImageBitmap(photo)
            avatar.setBackgroundColor(android.graphics.Color.TRANSPARENT)
            avatar.scaleType = ImageView.ScaleType.CENTER_CROP
        } else if (callerName.isNotEmpty()) {
            avatar.setImageDrawable(null)
            avatar.setBackgroundColor(getInitialsColor(callerName))
            avatar.scaleType = ImageView.ScaleType.CENTER
            val initial = callerName.first().uppercase()
            val tv = android.widget.TextView(this).apply {
                text = initial
                textSize = 36f
                setTextColor(android.graphics.Color.WHITE)
                typeface = android.graphics.Typeface.DEFAULT_BOLD
            }
            avatar.setImageDrawable(null)
            avatar.post {
                val w = avatar.width
                if (w > 0) {
                    val bmp = Bitmap.createBitmap(w, w, Bitmap.Config.ARGB_8888)
                    val canvas = android.graphics.Canvas(bmp)
                    tv.layout(0, 0, w, w)
                    tv.measure(
                        View.MeasureSpec.makeMeasureSpec(w, View.MeasureSpec.EXACTLY),
                        View.MeasureSpec.makeMeasureSpec(w, View.MeasureSpec.EXACTLY)
                    )
                    tv.draw(canvas)
                    avatar.setImageBitmap(bmp)
                }
            }
        }
    }

    private fun queryContactPhotoByNumber(number: String): Bitmap? {
        return try {
            val uri = Uri.withAppendedPath(
                ContactsContract.PhoneLookup.CONTENT_FILTER_URI,
                Uri.encode(number)
            )
            var cursor: Cursor? = null
            try {
                cursor = contentResolver.query(
                    uri,
                    arrayOf(ContactsContract.PhoneLookup.PHOTO_URI),
                    null, null, null
                )
                if (cursor != null && cursor.moveToFirst()) {
                    val photoUri = cursor.getString(0)
                    if (photoUri != null) {
                        var input: InputStream? = null
                        try {
                            input = contentResolver.openInputStream(Uri.parse(photoUri))
                            BitmapFactory.decodeStream(input)
                        } finally {
                            input?.close()
                        }
                    } else null
                } else null
            } finally {
                cursor?.close()
            }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to load contact photo: ${e.message}")
            null
        }
    }

    private fun getInitialsColor(name: String): Int {
        val colors = intArrayOf(
            0xFF4CAF50.toInt(), 0xFF2196F3.toInt(), 0xFFFF9800.toInt(),
            0xFF9C27B0.toInt(), 0xFF00BCD4.toInt(), 0xFFE91E63.toInt(),
            0xFF3F51B5.toInt(), 0xFF009688.toInt(), 0xFFFF5722.toInt(),
            0xFF673AB7.toInt()
        )
        return colors[Math.abs(name.hashCode()) % colors.size]
    }

    override fun onDestroy() {
        instance = null
        if (isRecording) {
            try {
                mediaRecorder?.apply { stop(); release() }
            } catch (_: Exception) {}
            mediaRecorder = null
            isRecording = false
        }
        try {
            if (wakeLock?.isHeld == true) wakeLock?.release()
        } catch (_: Exception) {}
        super.onDestroy()
    }
}
