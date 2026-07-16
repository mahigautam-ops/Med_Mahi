package com.example.med_caller

import android.content.Context
import android.telecom.Call
import android.telecom.Call.Callback
import android.util.Log
import io.flutter.plugin.common.EventChannel

/**
 * Singleton bridge: Android Telecom call lifecycle → Flutter EventChannel.
 *
 * Each event map contains:
 *   "state"      → RINGING | DIALING | ACTIVE | HOLDING | ENDED | CONNECTING
 *   "number"     → Normalized phone number (E.164 scheme-specific part)
 *   "callerName" → Caller display name from Telecom (CNAM / SIM phonebook)
 *                  or from device contacts via ContactsContract
 */
object CallStateManager {
    private const val TAG = "CallStateManager"
    const val CALL_EVENT_CHANNEL = "com.medcaller.call_state_events"
    const val CALL_METHOD_CHANNEL = "com.medcaller.call_control"

    private var eventSink: EventChannel.EventSink? = null
    private var currentCall: Call? = null

    // Cache events when Flutter engine is not alive
    private var cachedEvent: Map<String, String>? = null

    private var appContext: Context? = null

    fun setContext(ctx: Context) {
        appContext = ctx.applicationContext
    }

    /** Check if Flutter engine is connected and listening */
    fun isFlutterConnected(): Boolean = eventSink != null

    // Called from MedCallerInCallService when a call is added
    fun onCallAdded(call: Call) {
        currentCall = call
        val number = call.details?.handle?.schemeSpecificPart ?: "unknown"
        Log.d(TAG, "╔══════════════════════════════════════════════════╗")
        Log.d(TAG, "║  onCallAdded in CallStateManager                 ║")
        Log.d(TAG, "║  Number: $number | State: ${call.state}")
        Log.d(TAG, "║  Flutter connected: ${eventSink != null}")
        Log.d(TAG, "╚══════════════════════════════════════════════════╝")

        call.registerCallback(object : Callback() {
            override fun onStateChanged(call: Call, state: Int) {
                Log.d(TAG, "Call state changed → $state (Flutter: ${eventSink != null})")
                notifyFlutter(eventFor(state, call))
            }
            override fun onDetailsChanged(call: Call, details: Call.Details) {
                Log.d(TAG, "Call details changed (Flutter: ${eventSink != null})")
                notifyFlutter(eventFor(call.state, call))
            }
        })

        notifyFlutter(eventFor(call.state, call))
    }

    fun onCallRemoved(call: Call) {
        val number = call.details?.handle?.schemeSpecificPart ?: "unknown"
        Log.d(TAG, "onCallRemoved — Number: $number")
        currentCall = null
        notifyFlutter(mapOf("state" to "ENDED", "number" to "", "callerName" to ""))
    }

    fun setEventSink(sink: EventChannel.EventSink?) {
        val wasNull = eventSink == null
        eventSink = sink
        Log.d(TAG, "setEventSink: ${sink != null} (was null: $wasNull)")

        // If Flutter just connected and we have a cached event, replay it
        if (sink != null && wasNull && cachedEvent != null) {
            Log.d(TAG, "Replaying cached event: $cachedEvent")
            notifyFlutter(cachedEvent!!)
            cachedEvent = null
        }
    }

    // ── Call controls ──────────────────────────────────────────────────────────

    fun answerCall() {
        Log.d(TAG, "answerCall")
        currentCall?.answer(0)
    }
    fun rejectCall() {
        Log.d(TAG, "rejectCall")
        currentCall?.reject(false, null)
    }
    fun hangupCall() {
        Log.d(TAG, "hangupCall")
        currentCall?.disconnect()
    }

    fun holdCall() {
        Log.d(TAG, "holdCall")
        if (currentCall?.details?.can(Call.Details.CAPABILITY_HOLD) == true) {
            currentCall?.hold()
        }
    }

    fun unholdCall() {
        Log.d(TAG, "unholdCall")
        currentCall?.unhold()
    }

    fun muteCall(mute: Boolean) {
        Log.d(TAG, "muteCall: $mute")
        MedCallerInCallService.instance?.setMuted(mute)
    }

    fun toggleSpeaker(enabled: Boolean) {
        Log.d(TAG, "toggleSpeaker: $enabled")
        MedCallerInCallService.instance?.setSpeaker(enabled)
    }

    fun playDtmf(digit: Char) {
        Log.d(TAG, "playDtmf: $digit")
        currentCall?.playDtmfTone(digit)
        currentCall?.stopDtmfTone()
    }

    // ── Event building ─────────────────────────────────────────────────────────

    private fun eventFor(state: Int, call: Call): Map<String, String> {
        val stateStr = when (state) {
            Call.STATE_RINGING      -> "RINGING"
            Call.STATE_DIALING      -> "DIALING"
            Call.STATE_ACTIVE       -> "ACTIVE"
            Call.STATE_HOLDING      -> "HOLDING"
            Call.STATE_DISCONNECTED -> "ENDED"
            Call.STATE_CONNECTING   -> "CONNECTING"
            else                    -> "UNKNOWN"
        }

        val number = call.details?.handle?.schemeSpecificPart ?: ""
        val normalizedNumber = if (number.isNotEmpty())
            CallReceiver.normalizeNumber(number) else ""

        var callerName = call.details?.callerDisplayName ?: ""
        if (callerName.isEmpty() && normalizedNumber.isNotEmpty() && appContext != null) {
            callerName = CallReceiver.resolveContactName(appContext!!, normalizedNumber)
        }

        return mapOf(
            "state"      to stateStr,
            "number"     to normalizedNumber,
            "callerName" to callerName
        )
    }

    private fun notifyFlutter(event: Map<String, String>) {
        if (eventSink != null) {
            Log.d(TAG, "notifyFlutter → ${event["state"]} #${event["number"]}")
            eventSink?.success(event)
        } else {
            // Flutter engine not alive — cache the event for replay
            Log.d(TAG, "Flutter NOT connected — caching event: ${event["state"]}")
            cachedEvent = event
        }
    }
}
