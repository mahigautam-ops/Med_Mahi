package com.example.med_caller

import android.content.Intent
import android.telecom.Call
import android.telecom.InCallService
import android.telecom.CallAudioState
import android.util.Log

class MedCallerInCallService : InCallService() {

    companion object {
        private const val TAG = "MedCallerInCallService"
        var instance: MedCallerInCallService? = null
    }

    override fun onCreate() {
        super.onCreate()
        instance = this
        Log.d(TAG, "=== InCallService CREATED ===")
    }

    override fun onDestroy() {
        Log.d(TAG, "=== InCallService DESTROYED ===")
        instance = null
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): android.os.IBinder? {
        Log.d(TAG, "onBind — Telecom binding to us")
        return super.onBind(intent)
    }

    override fun onUnbind(intent: Intent?): Boolean {
        Log.d(TAG, "onUnbind — Telecom unbinding")
        return super.onUnbind(intent)
    }

    override fun onCallAdded(call: Call) {
        super.onCallAdded(call)
        val rawNumber = call.details?.handle?.schemeSpecificPart ?: "unknown"
        val state = call.state
        val normalized = CallReceiver.normalizeNumber(rawNumber)
        val callerName = if (normalized.isNotEmpty()) CallReceiver.resolveContactName(this, normalized) else ""
        Log.d(TAG, "╔══════════════════════════════════════════════════╗")
        Log.d(TAG, "║  onCallAdded — CALL DETECTED BY INCALLSERVICE   ║")
        Log.d(TAG, "║  Number: $normalized | State: $state")
        Log.d(TAG, "║  Flutter connected: ${CallStateManager.isFlutterConnected()}")
        Log.d(TAG, "╚══════════════════════════════════════════════════╝")

        CallStateManager.onCallAdded(call)

        if (state == Call.STATE_RINGING) {
            // Show incoming notification with full-screen intent (primary path)
            MedCallerForegroundService.showIncomingCall(normalized, callerName)

            // Only launch IncomingCallActivity directly if not in foreground
            if (!MainActivity.isInForeground) {
                launchIncomingCallActivity(normalized, callerName)
            }
        }

        call.registerCallback(object : Call.Callback() {
            override fun onStateChanged(call: Call, state: Int) {
                Log.d(TAG, "Call state changed → $state")
                when (state) {
                    Call.STATE_ACTIVE -> {
                        MedCallerForegroundService.showOngoingCall(normalized, callerName)
                        IncomingCallActivity.instance?.onCallActive()
                    }
                    Call.STATE_DISCONNECTED -> {
                        MedCallerForegroundService.stopCallNotifications()
                        IncomingCallActivity.instance?.finish()
                    }
                }
            }
        })
    }

    override fun onCallRemoved(call: Call) {
        val number = call.details?.handle?.schemeSpecificPart ?: "unknown"
        Log.d(TAG, "onCallRemoved — Number: $number")
        IncomingCallActivity.instance?.finish()
        super.onCallRemoved(call)
        CallStateManager.onCallRemoved(call)
    }

    override fun onCallAudioStateChanged(audioState: CallAudioState?) {
        Log.d(TAG, "onCallAudioStateChanged — route: ${audioState?.route}")
    }

    private fun launchIncomingCallActivity(number: String, callerName: String) {
        try {
            val intent = Intent(this, IncomingCallActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_NO_ANIMATION
                putExtra(IncomingCallActivity.EXTRA_NUMBER, number)
                putExtra(IncomingCallActivity.EXTRA_CALLER_NAME, callerName)
                putExtra(IncomingCallActivity.EXTRA_CALL_STATE, "RINGING")
            }
            startActivity(intent)
            Log.d(TAG, "IncomingCallActivity launched (direct)")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to launch IncomingCallActivity: ${e.message}", e)
        }
    }

    fun setSpeaker(enabled: Boolean) {
        if (enabled) {
            setAudioRoute(CallAudioState.ROUTE_SPEAKER)
        } else {
            setAudioRoute(CallAudioState.ROUTE_WIRED_OR_EARPIECE)
        }
    }
}
