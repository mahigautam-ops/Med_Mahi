import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/speech_service.dart';
import '../services/ai_service.dart';
import '../services/firebase_service.dart';
import '../providers/ai_settings.dart';

enum CallState { idle, ringing, dialing, active, holding, ended }

class CallProvider extends ChangeNotifier {
  static const _stateChannel =
      EventChannel('com.medcaller.call_state_events');
  static const _controlChannel =
      MethodChannel('com.medcaller.call_control');
  static const _dialerChannel =
      MethodChannel('com.medcaller.dialer');
  static const _recordingChannel =
      MethodChannel('com.medcaller.recording');

  StreamSubscription? _sub;
  final FirebaseService _firebaseService = FirebaseService();
  AiSettingsProvider? _aiSettings;
  SpeechAIService? _speechAI;

  CallState _state = CallState.idle;
  String _number = '';
  String _callerName = ''; // resolved contact/CNAM name from Android
  bool _isMuted = false;
  bool _isOnHold = false;
  bool _isSpeakerOn = false;
  bool _isDefaultDialer = false;
  bool _isRecording = false;
  String? _recordingPath;
  bool _isProcessingRecording = false;
  Duration _callDuration = Duration.zero;

  CallState get state => _state;
  String get number => _number;
  String get callerName => _callerName;
  bool get isMuted => _isMuted;
  bool get isOnHold => _isOnHold;
  bool get isSpeakerOn => _isSpeakerOn;
  bool get isDefaultDialer => _isDefaultDialer;
  bool get isRecording => _isRecording;
  String? get recordingPath => _recordingPath;
  bool get isProcessingRecording => _isProcessingRecording;
  bool get isInCall =>
      _state == CallState.ringing ||
      _state == CallState.dialing ||
      _state == CallState.active ||
      _state == CallState.holding;

  String get liveTranscript => _speechAI?.fullTranscript ?? '';
  String get livePartialWords => _speechAI?.currentWords ?? '';

  Future<void> initialize() async {
    await checkDefaultDialer();

    _sub = _stateChannel.receiveBroadcastStream().listen(
      (event) {
        if (event is Map) {
          final s = event['state'] as String? ?? '';
          final n = event['number'] as String? ?? '';
          final name = event['callerName'] as String? ?? '';
          _number = n;
          _callerName = name;
          final previousState = _state;
          _state = _parseState(s);

          debugPrint(
            '[CallProvider] state=$s number=$n callerName=$name',
          );
          notifyListeners();

          if (previousState != CallState.ended && _state == CallState.ended) {
            _onCallEnded();
          }
        }
      },
      onError: (e) => debugPrint('[CallProvider] EventChannel error: $e'),
    );
  }

  // ── Dialer controls ────────────────────────────────────────────────────────

  Future<void> makeCall(String number) async {
    try {
      await _dialerChannel.invokeMethod('makeCall', {'number': number});
    } catch (e) {
      debugPrint('[CallProvider] makeCall error: $e');
      rethrow;
    }
  }

  Future<void> requestDefaultDialer() async {
    await _dialerChannel.invokeMethod('requestDefaultDialer');
  }

  Future<void> checkDefaultDialer() async {
    try {
      final result =
          await _dialerChannel.invokeMethod<bool>('isDefaultDialer');
      _isDefaultDialer = result ?? false;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> startBackgroundService() async {
    try {
      await _dialerChannel.invokeMethod('startService');
    } catch (e) {
      debugPrint('[CallProvider] startService error: $e');
    }
  }

  Future<void> stopBackgroundService() async {
    try {
      await _dialerChannel.invokeMethod('stopService');
    } catch (e) {
      debugPrint('[CallProvider] stopService error: $e');
    }
  }

  Future<void> requestIgnoreBatteryOptimization() async {
    try {
      await _dialerChannel.invokeMethod('ignoreBatteryOptimization');
    } catch (e) {
      debugPrint('[CallProvider] batteryOptimization error: $e');
    }
  }

  // ── In-call controls ───────────────────────────────────────────────────────

  Future<void> answerCall() async =>
      _controlChannel.invokeMethod('answerCall');

  Future<void> rejectCall() async =>
      _controlChannel.invokeMethod('rejectCall');

  Future<void> hangupCall() async =>
      _controlChannel.invokeMethod('hangupCall');

  Future<void> toggleHold() async {
    if (_isOnHold) {
      await _controlChannel.invokeMethod('unholdCall');
      _isOnHold = false;
    } else {
      await _controlChannel.invokeMethod('holdCall');
      _isOnHold = true;
    }
    notifyListeners();
  }

  Future<void> toggleMute() async {
    _isMuted = !_isMuted;
    await _controlChannel.invokeMethod('mute', {'mute': _isMuted});
    notifyListeners();
  }

  Future<void> toggleSpeaker() async {
    _isSpeakerOn = !_isSpeakerOn;
    await _controlChannel.invokeMethod('toggleSpeaker', {'speaker': _isSpeakerOn});
    notifyListeners();
  }

  Future<void> playDtmf(String digit) async {
    await _controlChannel.invokeMethod('playDtmf', {'digit': digit});
  }

  // ── Recording controls ──────────────────────────────────────────────────

  Future<void> toggleRecording() async {
    if (_isRecording) {
      _recordingPath = await _recordingChannel.invokeMethod<String>('stopRecording');
      _speechAI?.stopListeningAndGenerate();
      _isRecording = false;
      debugPrint('[CallProvider] Recording stopped: $_recordingPath');
    } else {
      final status = await Permission.microphone.request();
      if (!status.isGranted) {
        debugPrint('[CallProvider] Microphone permission denied');
        return;
      }
      final path = await _recordingChannel.invokeMethod<String>('startRecording');
      if (path != null) {
        _isRecording = true;
        _recordingPath = path;
        debugPrint('[CallProvider] Recording started: $path');

        // Start speech recognition in parallel
        if (_speechAI != null) {
          await _speechAI!.startListening();
        }
      }
    }
    notifyListeners();
  }

  Future<String?> stopRecordingIfActive() async {
    if (_isRecording) {
      _recordingPath = await _recordingChannel.invokeMethod<String>('stopRecording');
      _isRecording = false;
      notifyListeners();
      return _recordingPath;
    }
    return null;
  }

  // ── End-call pipeline ────────────────────────────────────────────────────

  void setAiSettings(AiSettingsProvider settings) {
    _aiSettings = settings;
    _speechAI = SpeechAIService(settings);
  }

  void _onCallEnded() async {
    await stopRecordingIfActive();

    // Stop speech recognition and get transcript
    String transcript = '';
    if (_speechAI != null && _speechAI!.isListening) {
      final result = await _speechAI!.stopListeningAndGenerate();
      transcript = _speechAI!.fullTranscript;
      debugPrint('[CallProvider] Speech transcript: ${transcript.substring(0, transcript.length > 100 ? 100 : transcript.length)}...');
    }

    if (transcript.isEmpty) {
      debugPrint('[CallProvider] No transcript captured — skipping pipeline');
      _callDuration = Duration.zero;
      notifyListeners();
      return;
    }

    if (_aiSettings == null || !_aiSettings!.isConfigured) {
      debugPrint('[CallProvider] AI not configured — skipping summary (transcript saved to timeline)');
    }

    _isProcessingRecording = true;
    notifyListeners();

    try {
      // Generate AI summary from transcript
      AISummaryResult? result;
      if (_aiSettings != null && _aiSettings!.isConfigured) {
        try {
          result = await AIService(_aiSettings!).generateMedicalSummary(transcript);
        } catch (e) {
          debugPrint('[CallProvider] AI summary failed: $e');
        }
      }

      final patientPhone = _number;
      if (patientPhone.isNotEmpty) {
        final summaryData = result != null
            ? {
                'symptoms': result.symptomsSummary,
                'medicines': result.medicinesSummary,
                'condition': result.conditionSummary,
                'lifestyle': result.lifestyle,
                'sleepIssues': result.sleepIssues,
                'emotionalState': result.emotionalState,
                'treatmentUpdate': result.treatmentUpdate,
                'followUp': result.followUp,
                'suggestedStatus': result.suggestedStatus,
                'timelineEntry': result.timelineEntry,
                'improvementPercent': result.improvementPercent,
              }
            : <String, dynamic>{};

        await _firebaseService.addCallRecordingEvent(
          patientPhone: patientPhone,
          transcript: transcript,
          aiSummary: summaryData,
          duration: _callDurationStr,
        );

        debugPrint('[CallProvider] Timeline + patient record updated for $patientPhone');
      }
    } catch (e) {
      debugPrint('[CallProvider] Recording pipeline error: $e');
    } finally {
      _isProcessingRecording = false;
      _callDuration = Duration.zero;
      _speechAI?.clearTranscript();
      notifyListeners();
    }
  }

  void updateCallDuration(Duration duration) {
    _callDuration = duration;
  }

  String get _callDurationStr {
    final m = _callDuration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = _callDuration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  CallState _parseState(String s) {
    switch (s) {
      case 'RINGING':    return CallState.ringing;
      case 'DIALING':    return CallState.dialing;
      case 'ACTIVE':     return CallState.active;
      case 'HOLDING':    return CallState.holding;
      case 'ENDED':      return CallState.ended;
      default:           return CallState.idle;
    }
  }

  String get stateLabel {
    switch (_state) {
      case CallState.ringing:    return 'Incoming Call';
      case CallState.dialing:    return 'Calling...';
      case CallState.active:     return 'Active Call';
      case CallState.holding:    return 'On Hold';
      case CallState.ended:      return 'Call Ended';
      default:                   return '';
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
