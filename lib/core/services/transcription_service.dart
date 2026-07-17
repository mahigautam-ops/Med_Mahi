import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/ai_settings.dart';
import 'ai_service.dart';

class TranscriptionService {
  String _whisperApiKey = '';
  String _whisperEndpoint = 'https://api.openai.com/v1/audio/transcriptions';
  String _whisperModel = 'whisper-1';

  static const _kWhisperKey = 'whisper_api_key';

  bool get isConfigured => _whisperApiKey.isNotEmpty;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _whisperApiKey = prefs.getString(_kWhisperKey) ?? '';
  }

  Future<void> updateApiKey(String key) async {
    _whisperApiKey = key.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kWhisperKey, _whisperApiKey);
  }

  Future<String> transcribe(String wavFilePath) async {
    if (!isConfigured) {
      throw AIException(
        'Whisper API not configured',
        'Set OpenAI API key in Admin Panel → AI Settings → Transcription.',
      );
    }

    final file = File(wavFilePath);
    if (!await file.exists()) {
      throw AIException('File not found', 'Recording file does not exist: $wavFilePath');
    }

    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) {
      throw AIException('Empty file', 'Recording file is empty.');
    }

    final request = http.MultipartRequest('POST', Uri.parse(_whisperEndpoint));
    request.headers['Authorization'] = 'Bearer $_whisperApiKey';
    request.fields['model'] = _whisperModel;
    request.fields['language'] = 'en';
    request.fields['response_format'] = 'text';
    request.files.add(http.MultipartFile.fromBytes(
      'file',
      bytes,
      filename: 'call_recording.wav',
    ));

    try {
      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 120),
      );
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        return response.body.trim();
      }

      if (response.statusCode == 401) {
        throw AIException(
          'Invalid API Key',
          'The Whisper API key is invalid. Update it in Admin Panel.',
        );
      }

      throw AIException('Transcription Error ${response.statusCode}', response.body);
    } catch (e) {
      if (e is AIException) rethrow;
      throw AIException('Transcription failed', 'Check internet connection and try again.');
    }
  }

  Future<AISummaryResult> transcribeAndSummarize(
    String wavFilePath,
    AiSettingsProvider aiSettings,
  ) async {
    final transcript = await transcribe(wavFilePath);
    if (transcript.isEmpty) {
      throw AIException('No speech detected', 'The recording appears to be silent.');
    }

    final aiService = AIService(aiSettings);
    return await aiService.generateMedicalSummary(transcript);
  }
}
