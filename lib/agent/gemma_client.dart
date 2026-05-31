import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
class GemmaModelClient {
  final String modelPath;

  InferenceModel? _model;
  bool _supportsImage = false;

  GemmaModelClient(this.modelPath);

  /// Load the model. When [withVision] is set we try to enable multimodal image
  /// input; if the model file has no vision encoder that fails, so we
  /// transparently fall back to a text-only load and the chat still works.
  Future<void> loadModel({bool withVision = false}) async {
    debugPrint('[gemma] Installing model from file: $modelPath');
    await FlutterGemma.installModel(
      modelType: ModelType.gemmaIt,
    ).fromFile(modelPath).install();
    debugPrint('[gemma] Model installed, loading (vision=$withVision)...');

    if (withVision) {
      try {
        _model = await FlutterGemma.getActiveModel(
          maxTokens: 2048,
          supportImage: true,
          maxNumImages: 1,
        );
        _supportsImage = true;
        debugPrint('[gemma] Model ready (vision enabled)');
        return;
      } catch (e) {
        debugPrint('[gemma] Vision load failed ($e); falling back to text-only');
      }
    }

    _model = await FlutterGemma.getActiveModel(maxTokens: 2048);
    _supportsImage = false;
    debugPrint('[gemma] Model ready (text-only)');
  }

  /// Run one completion over [messages] (the last entry is the current user
  /// turn). When [image] is supplied and the model supports vision, it is
  /// attached to that final user turn.
  Future<String> complete(
    String system,
    List<Map<String, dynamic>> messages, {
    int maxTokens = 512,
    Uint8List? image,
  }) async {
    if (_model == null) throw Exception('Model not loaded');

    final chat = await _model!.createChat();

    // Prepend the system prompt to the first user message, then replay history.
    // The final message is always treated as a user turn.
    bool systemInjected = false;
    for (int i = 0; i < messages.length; i++) {
      final m = messages[i];
      final isLast = i == messages.length - 1;
      final isUser = isLast || m['role'] == 'user';
      var text = m['content']?.toString() ?? '';
      if (isUser && !systemInjected) {
        text = '$system\n\n$text';
        systemInjected = true;
      }
      if (isLast && isUser && image != null && _supportsImage) {
        await chat.addQueryChunk(
          Message.withImage(text: text, imageBytes: image, isUser: true),
        );
      } else {
        await chat.addQueryChunk(Message(text: text, isUser: isUser));
      }
    }

    final response = await chat.generateChatResponse();
    try {
      await chat.session.close();
    } catch (_) {}
    if (response is TextResponse) return response.token;
    return response.toString();
  }

  Future<void> dispose() async {
    await _model?.close();
    _model = null;
  }
}
