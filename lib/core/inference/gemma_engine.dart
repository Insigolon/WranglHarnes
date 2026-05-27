import 'dart:typed_data';

import '../../agent/gemma_client.dart';

class GemmaEngine {
  GemmaModelClient? _client;

  bool get isLoaded => _client != null;

  Future<void> loadModel(String modelPath, {bool withVision = false}) async {
    _client = GemmaModelClient(modelPath);
    await _client!.loadModel(withVision: withVision);
  }

  Future<String> generate(
    String prompt, {
    String system = '',
    List<Map<String, dynamic>> history = const [],
    int maxTokens = 512,
  }) async {
    if (_client == null) throw Exception('Model not loaded');
    return _client!.complete(system, history, maxTokens: maxTokens);
  }

  Future<String> generateWithImage(
    String prompt,
    Uint8List image, {
    String system = '',
    List<Map<String, dynamic>> history = const [],
    int maxTokens = 512,
  }) async {
    if (_client == null) throw Exception('Model not loaded');
    return _client!.complete(
      system,
      history,
      maxTokens: maxTokens,
      image: image,
    );
  }

  Future<void> dispose() async {
    await _client?.dispose();
    _client = null;
  }
}
