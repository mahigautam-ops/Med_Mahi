import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/ai_settings.dart';
import 'ai_service.dart';

class TranscriptionService {
  String _apiKey = '';
  static const _kGoogleSttKey = 'google_stt_api_key';
  static const _endpoint = 'https://speech.googleapis.com/v1/speech:recognize';

  bool get isConfigured => _apiKey.isNotEmpty;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _apiKey = prefs.getString(_kGoogleSttKey) ?? '';
  }

  Future<void> updateApiKey(String key) async {
    _apiKey = key.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kGoogleSttKey, _apiKey);
  }

  Future<String> transcribe(String wavFilePath) async {
    if (!isConfigured) {
      throw AIException(
        'Google STT not configured',
        'Set Google Cloud API key in Admin Panel → AI Settings → Transcription.',
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

    final audioBase64 = base64Encode(bytes);

    final requestBody = jsonEncode({
      'config': {
        'encoding': 'LINEAR16',
        'sampleRateHertz': 44100,
        'languageCode': 'en-IN',
        'alternativeLanguageCodes': ['en-US'],
        'model': 'phone_call',
        'enableAutomaticPunctuation': true,
        'enableWordTimeOffsets': false,
        'audioChannelCount': 1,
        'useEnhanced': true,
      },
      'audio': {
        'content': audioBase64,
      },
    });

    try {
      final response = await http
          .post(
            Uri.parse('$_endpoint?key=$_apiKey'),
            headers: {'Content-Type': 'application/json'},
            body: requestBody,
          )
          .timeout(const Duration(seconds: 120));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final results = data['results'] as List? ?? [];

        final transcriptParts = <String>[];
        for (final result in results) {
          final alternatives = result['alternatives'] as List? ?? [];
          if (alternatives.isNotEmpty) {
            final transcript = alternatives[0]['transcript']?.toString() ?? '';
            if (transcript.isNotEmpty) {
              transcriptParts.add(transcript);
            }
          }
        }

        return transcriptParts.join(' ').trim();
      }

      if (response.statusCode == 403) {
        throw AIException(
          'API key invalid or STT not enabled',
          'Enable Speech-to-Text API in Google Cloud Console.',
        );
      }

      throw AIException(
        'Transcription Error ${response.statusCode}',
        response.body,
      );
    } catch (e) {
      if (e is AIException) rethrow;
      throw AIException(
        'Transcription failed',
        'Check internet connection and try again.',
      );
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
