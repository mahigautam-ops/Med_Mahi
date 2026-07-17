package com.example.med_caller

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

class CallActionReceiver : BroadcastReceiver() {
    companion object {
        private const val TAG = "CallActionReceiver"
        const val ACTION_ACCEPT = "com.example.med_caller.ACTION_ACCEPT"
        const val ACTION_DECLINE = "com.example.med_caller.ACTION_DECLINE"
    }

    override fun onReceive(context: Context, intent: Intent?) {
        Log.d(TAG, "onReceive: ${intent?.action}")
        when (intent?.action) {
            ACTION_ACCEPT -> {
                Log.d(TAG, "Accept from notification")
                CallStateManager.answerCall()
            }
            ACTION_DECLINE -> {
                Log.d(TAG, "Decline from notification")
                CallStateManager.rejectCall()
            }
        }
    }
}
