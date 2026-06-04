// lib/services/on_device_llm_service.dart

import 'package:flutter/foundation.dart'; 
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

class OnDeviceLlmService {
  static final OnDeviceLlmService instance = OnDeviceLlmService._();
  OnDeviceLlmService._();

  InferenceModel? _model;
  bool _isReady = false;

  bool get isReady => _isReady;

/// Call once at app startup. Shows download progress via [onProgress].
  Future<void> init({void Function(double progress)? onProgress}) async {
    try {
      // 1. The FlutterGemma engine must be initialized before doing anything else
      await FlutterGemma.initialize();

      // 2. Install the model directly from the asset bundle.
      // Do NOT use dart:io File objects for Flutter assets!
      await FlutterGemma.installModel(
        modelType: ModelType.gemmaIt,
        fileType: ModelFileType.task,
      ).fromAsset('assets/models/gemma3-1b-it-int4.task').install(); 

      // 3. Create the model instance
      _model = await FlutterGemma.getActiveModel(
        maxTokens: 2048,
        preferredBackend: PreferredBackend.cpu,
      );

      _isReady = true;
    } catch (e) {
      debugPrint('[OnDeviceLLM] init failed: $e');
      _isReady = false;
    }
  }
  /// Drop-in replacement for _correctSentenceWithGemini
  Future<String> correctBimSentence(List<String> signs) async {
    if (!_isReady || _model == null) return signs.join(' ');

    final raw = signs.join(' ');
    final prompt = '''You are a BIM transcription system.

TASK:
Convert signs into text WITHOUT adding, expanding, or explaining anything.

ABSOLUTE RULES:

1. Output must ONLY contain transformations of input tokens.

2. NEVER generate new words not present in input.

3. NEVER form full sentences unless explicitly present in input.

4. NEVER interpret single letters into meanings.

5. NEVER add grammar words (e.g. "saya", "adalah", "ialah").

6. If input is a single letter or unclear sign:
   → output it unchanged.

7. If input is empty or meaningless:
   → output empty string.

8. Do not be helpful. Do not complete sentences.

Signs:
$raw

Output:


''';

    try {
      final session = await _model!.createSession();
      
      // 5. New Session API (getResponse no longer accepts arguments directly)
      await session.addQueryChunk(
        Message.text(
          text: prompt,
          isUser: true,
        ),
      );
      
      final response = await session.getResponse();
      await session.close();

      print("response: ${response}");
      
      return response.trim().isNotEmpty ? response.trim() : raw;
    } catch (e) {
      debugPrint('[OnDeviceLLM] inference failed: $e');
      return raw;
    }
  }

  Future<void> dispose() async {
    // There is no longer a strict requirement to close the model itself, 
    // just the individual sessions. 
    _isReady = false;
  }
}