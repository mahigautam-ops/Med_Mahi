package com.example.med_caller

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioAttributes
import android.media.Ringtone
import android.media.RingtoneManager
import android.os.Build
import android.os.IBinder
import android.telephony.TelephonyManager
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.Person

class MedCallerForegroundService : Service() {

    private var callReceiver: CallReceiver? = null
    private var ringtone: Ringtone? = null

    companion object {
        private const val TAG = "MedCallerService"
        const val CHANNEL_BG = "medcaller_bg_channel"
        const val CHANNEL_CALL = "medcaller_call_channel"
        const val NOTIF_ID = 1001

        private var instance: MedCallerForegroundService? = null

        fun start(context: Context) {
            val intent = Intent(context, MedCallerForegroundService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
            Log.d(TAG, "Service start requested")
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, MedCallerForegroundService::class.java))
        }

        fun onCallEvent(event: Map<String, String>) {
            Log.d(TAG, "onCallEvent: ${event["event"]} #${event["number"]}")
        }

        fun showIncomingCall(number: String, callerName: String) {
            val svc = instance ?: return
            svc.playRingtone()
            svc.showIncomingNotification(number, callerName)
        }

        fun showOngoingCall(number: String, callerName: String) {
            val svc = instance ?: return
            svc.stopRingtone()
            svc.showOngoingNotification(number, callerName)
        }

        fun stopCallNotifications() {
            val svc = instance ?: return
            svc.stopRingtone()
            svc.revertToBackgroundNotification()
        }
    }

    override fun onCreate() {
        super.onCreate()
        instance = this
        createNotificationChannels()
        startForeground(NOTIF_ID, buildBackgroundNotification())
        registerCallReceiver()
        Log.d(TAG, "Service created — BroadcastReceiver registered")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (callReceiver == null) {
            registerCallReceiver()
        }
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        instance = null
        stopRingtone()
        unregisterCallReceiver()
        stopForeground(STOP_FOREGROUND_REMOVE)
        super.onDestroy()
        Log.d(TAG, "Service destroyed")
    }

    // ── CallReceiver ────────────────────────────────────────────────────────────

    private fun registerCallReceiver() {
        if (callReceiver != null) return
        callReceiver = CallReceiver(null)
        val filter = IntentFilter(TelephonyManager.ACTION_PHONE_STATE_CHANGED)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                registerReceiver(callReceiver, filter, Context.RECEIVER_EXPORTED)
            } else {
                registerReceiver(callReceiver, filter)
            }
            Log.d(TAG, "CallReceiver registered in service")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to register receiver: ${e.message}")
        }
    }

    private fun unregisterCallReceiver() {
        callReceiver?.let {
            runCatching { unregisterReceiver(it) }
            callReceiver = null
        }
    }

    // ── Ringtone ─────────────────────────────────────────────────────────────────

    private fun playRingtone() {
        try {
            val uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
            ringtone = RingtoneManager.getRingtone(this, uri)
            ringtone?.audioAttributes = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()
            ringtone?.isLooping = true
            ringtone?.play()
            Log.d(TAG, "Ringtone started from service")
        } catch (e: Exception) {
            Log.e(TAG, "Ringtone error: ${e.message}")
        }
    }

    private fun stopRingtone() {
        try {
            ringtone?.stop()
            ringtone = null
        } catch (_: Exception) {}
    }

    // ── Notifications ────────────────────────────────────────────────────────────

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val bgChannel = NotificationChannel(
                CHANNEL_BG,
                "MedCaller Background",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Keeps MedCaller running for incoming call identification"
                setShowBadge(false)
            }
            (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                .createNotificationChannel(bgChannel)

            val callChannel = NotificationChannel(
                CHANNEL_CALL,
                "Call Notifications",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Incoming and ongoing call notifications"
                setShowBadge(true)
            }
            (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                .createNotificationChannel(callChannel)
        }
    }

    private fun buildBackgroundNotification(): Notification {
        val pendingIntent = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
            },
            PendingIntent.FLAG_IMMUTABLE
        )
        return NotificationCompat.Builder(this, CHANNEL_BG)
            .setContentTitle("MedCaller")
            .setContentText("Running in background \u2014 ready to identify callers")
            .setSmallIcon(android.R.drawable.ic_menu_call)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }

    private fun showIncomingNotification(number: String, callerName: String) {
        val activityIntent = Intent(this, IncomingCallActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK
            putExtra(IncomingCallActivity.EXTRA_NUMBER, number)
            putExtra(IncomingCallActivity.EXTRA_CALLER_NAME, callerName)
            putExtra(IncomingCallActivity.EXTRA_CALL_STATE, "RINGING")
        }
        val fullScreenIntent = PendingIntent.getActivity(
            this, 0, activityIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val acceptIntent = PendingIntent.getBroadcast(
            this, 1,
            Intent(this, CallActionReceiver::class.java)
                .setAction(CallActionReceiver.ACTION_ACCEPT),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val declineIntent = PendingIntent.getBroadcast(
            this, 2,
            Intent(this, CallActionReceiver::class.java)
                .setAction(CallActionReceiver.ACTION_DECLINE),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val displayName = callerName.ifEmpty { number.ifEmpty { "Unknown Caller" } }

        val builder = NotificationCompat.Builder(this, CHANNEL_CALL)
            .setSmallIcon(android.R.drawable.ic_menu_call)
            .setContentTitle("Incoming Call")
            .setContentText(displayName)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setFullScreenIntent(fullScreenIntent, true)
            .setOngoing(true)
            .setAutoCancel(false)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val person = Person.Builder()
                .setName(displayName)
                .setImportant(true)
                .build()
            builder.setStyle(NotificationCompat.CallStyle.forIncomingCall(
                person, declineIntent, acceptIntent
            ))
        } else {
            builder.addAction(
                android.R.drawable.ic_menu_call,
                "Answer", acceptIntent
            )
            builder.addAction(
                android.R.drawable.ic_menu_close_clear_cancel,
                "Decline", declineIntent
            )
        }

        startForeground(NOTIF_ID, builder.build())
        Log.d(TAG, "Incoming call notification shown for $displayName")
    }

    private fun showOngoingNotification(number: String, callerName: String) {
        val activityIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT
        }
        val contentIntent = PendingIntent.getActivity(
            this, 0, activityIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val hangupIntent = PendingIntent.getBroadcast(
            this, 3,
            Intent(this, CallActionReceiver::class.java)
                .setAction(CallActionReceiver.ACTION_DECLINE),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val displayName = callerName.ifEmpty { number.ifEmpty { "Unknown" } }

        val builder = NotificationCompat.Builder(this, CHANNEL_CALL)
            .setSmallIcon(android.R.drawable.ic_menu_call)
            .setContentTitle("Ongoing Call")
            .setContentText(displayName)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setContentIntent(contentIntent)
            .setOngoing(true)
            .setAutoCancel(false)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val person = Person.Builder()
                .setName(displayName)
                .setImportant(true)
                .build()
            builder.setStyle(NotificationCompat.CallStyle.forOngoingCall(
                person, hangupIntent
            ))
        } else {
            builder.addAction(
                android.R.drawable.ic_menu_close_clear_cancel,
                "End Call", hangupIntent
            )
        }

        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.notify(NOTIF_ID, builder.build())
        Log.d(TAG, "Ongoing call notification shown for $displayName")
    }

    private fun revertToBackgroundNotification() {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.cancel(NOTIF_ID)
        startForeground(NOTIF_ID, buildBackgroundNotification())
        Log.d(TAG, "Reverted to background notification")
    }
}
