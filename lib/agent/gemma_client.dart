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
    // The final message is always treated as a user turn.
    bool systemInjected = false;
    for (int i = 0; i < messages.length; i++) {
      final m = messages[i];
      final isUser = i == messages.length - 1 || m['role'] == 'user';
      var text = m['content']?.toString() ?? '';
      if (isUser && !systemInjected) {
        text = '$system\n\n$text';
        systemInjected = true;
      }
      await chat.addQueryChunk(Message(text: text, isUser: isUser));
    }

    final response = await chat.generateChatResponse();
    if (response is TextResponse) return response.token;
    return response.toString();
  }

  Future<void> dispose() async {
    await _model?.close();
    _model = null;
  }
}
