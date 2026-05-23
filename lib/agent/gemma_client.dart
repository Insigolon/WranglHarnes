import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

class GemmaModelClient {
  final String modelPath;

  InferenceModel? _model;

  GemmaModelClient(this.modelPath);

  Future<void> loadModel() async {
    debugPrint('[gemma] Installing model from file: $modelPath');
    await FlutterGemma.installModel(modelType: ModelType.gemmaIt)
        .fromFile(modelPath)
        .install();
    debugPrint('[gemma] Model installed, loading...');
    _model = await FlutterGemma.getActiveModel(maxTokens: 2048);
    debugPrint('[gemma] Model ready');
  }

  Future<String> complete(
    String system,
    List<Map<String, dynamic>> messages, {
    int maxTokens = 512,
  }) async {
    if (_model == null) throw Exception('Model not loaded');

    final chat = await _model!.createChat();

    // Prepend the system prompt to the first user message, then replay history.
    bool systemInjected = false;
    for (int i = 0; i < messages.length - 1; i++) {
      final m = messages[i];
      final isUser = m['role'] == 'user';
      String text = m['content']?.toString() ?? '';
      if (isUser && !systemInjected) {
        text = '$system\n\n$text';
        systemInjected = true;
      }
      await chat.addQueryChunk(Message(text: text, isUser: isUser));
    }

    // Final user turn.
    final last = messages.last;
    String lastText = last['content']?.toString() ?? '';
    if (!systemInjected) {
      lastText = '$system\n\n$lastText';
    }
    await chat.addQueryChunk(Message(text: lastText, isUser: true));

    final response = await chat.generateChatResponse();
    if (response is TextResponse) return response.token;
    return response.toString();
  }

  Future<void> dispose() async {
    await _model?.close();
    _model = null;
  }
}
