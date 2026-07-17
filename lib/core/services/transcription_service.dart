import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:vosk_flutter_service/vosk_flutter_service.dart';
import '../providers/ai_settings.dart';
import 'ai_service.dart';

class TranscriptionService {
  static const _modelName = 'vosk-model-small-en-us-0.15';
  static const _sampleRate = 16000;

  VoskFlutterPlugin? _vosk;
  Model? _model;
  bool _initialized = false;
  bool _initializing = false;

  bool get isConfigured => true;

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    if (_initializing) return;
    _initializing = true;

    try {
      _vosk = VoskFlutterPlugin.instance();
      final modelLoader = ModelLoader();

      debugPrint('[TranscriptionService] Downloading/loading Vosk model...');
      final modelsList = await modelLoader.loadModelsList();
      final modelDesc = modelsList.firstWhere(
        (m) => m.name == _modelName,
        orElse: () => throw AIException(
          'Model not found',
          'Vosk model $_modelName not available',
        ),
      );
      final modelPath = await modelLoader.loadFromNetwork(modelDesc.url);
      _model = await _vosk!.createModel(modelPath);

      _initialized = true;
      debugPrint('[TranscriptionService] Vosk initialized');
    } catch (e) {
      _initializing = false;
      if (e is AIException) rethrow;
      throw AIException('Vosk init failed', e.toString());
    }
  }

  Future<void> load() async {}

  Future<void> updateApiKey(String key) async {}

  Future<String> transcribe(String wavFilePath) async {
    await _ensureInitialized();

    final file = File(wavFilePath);
    if (!await file.exists()) {
      throw AIException('File not found', 'Recording file does not exist: $wavFilePath');
    }

    final bytes = await file.readAsBytes();
    if (bytes.length <= 44) {
      throw AIException('Empty file', 'Recording file is too short.');
    }

    final pcmData = bytes.buffer.asUint8List(44);
    debugPrint('[TranscriptionService] PCM data: ${pcmData.length} bytes');

    final recognizer = await _vosk!.createRecognizer(
      model: _model!,
      sampleRate: _sampleRate,
    );

    try {
      final transcript = await _processAudio(recognizer, pcmData);
      debugPrint('[TranscriptionService] Transcript: ${transcript.length} chars');
      return transcript;
    } finally {
      await recognizer.close();
    }
  }

  Future<String> _processAudio(Recognizer recognizer, Uint8List pcmData) async {
    final results = <String>[];
    const chunkSize = 8192;
    var pos = 0;

    while (pos + chunkSize < pcmData.length) {
      final chunk = Uint8List.fromList(
        pcmData.getRange(pos, pos + chunkSize).toList(),
      );
      final resultReady = await recognizer.acceptWaveformBytes(chunk);
      pos += chunkSize;

      if (resultReady) {
        final result = await recognizer.getResult();
        final parsed = _parseResult(result);
        if (parsed.isNotEmpty) {
          results.add(parsed);
        }
      }
    }

    final finalResult = await recognizer.getFinalResult();
    final parsed = _parseResult(finalResult);
    if (parsed.isNotEmpty) {
      results.add(parsed);
    }

    return results.join(' ').trim();
  }

  String _parseResult(String jsonStr) {
    try {
      final data = jsonDecode(jsonStr);
      return data['text']?.toString() ?? '';
    } catch (_) {
      return jsonStr;
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
