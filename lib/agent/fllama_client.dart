import 'dart:async';
import 'dart:io';
import 'package:fllama/fllama.dart';
import 'package:flutter/foundation.dart';

class FLlamaModelClient {
  final String modelPath;
  double? _contextId;
  bool _isLoading = false;

  FLlamaModelClient(this.modelPath);

  /// Initialise the native context once; subsequent calls reuse it.
  Future<void> _ensureContext() async {
    if (_contextId != null) return;
    if (_isLoading) {
      while (_isLoading) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
      if (_contextId == null) {
        throw Exception('Model context failed to initialise');
      }
      return;
    }

    // Ensure the model file exists before initializing native context
    final file = File(modelPath);
    if (!await file.exists()) {
      throw Exception('Model file not found at: $modelPath');
    }
    debugPrint('[fllama] Model file size: ${await file.length()} bytes');
    _isLoading = true;
    try {
      final result = await Fllama.instance()
          ?.initContext(modelPath, emitLoadProgress: true);
      if (result == null) throw Exception('initContext returned null');

      final id = result['contextId'];
      if (id == null) throw Exception('No contextId in initContext result');

      // contextId comes back as a number; ensure it's a double.
      _contextId = (id is double) ? id : double.parse(id.toString());
      if (_contextId! <= 0) {
        _contextId = null;
        throw Exception('Invalid contextId: $id');
      }
      debugPrint('[fllama] Context loaded: $_contextId');
    } finally {
      _isLoading = false;
    }
  }

  /// Run a chat completion and return the full generated text.
  Future<String> complete(
    String system,
    List<Map<String, dynamic>> messages, {
    List<String>? tools,
    int maxTokens = 512,
  }) async {
    String finalSystem = system;

    if (tools != null && tools.isNotEmpty) {
      final toolHint =
          '\n\nAvailable tools (call exactly one per turn as JSON):\n' +
          tools.map((t) => '  - $t').join('\n') +
          '\n\nTo call a tool: {"tool": "<name>", "args": {...}}' +
          '\nTo give a final answer: {"answer": "<your answer>"}';
      finalSystem += toolHint;
    }

    // Manual format for TinyLlama/Phi-2 ChatML
    final buffer = StringBuffer();
    buffer.writeln('<|system|>\n$finalSystem</s>');
    for (var m in messages) {
      final role = m['role'] == 'user' ? 'user' : 'assistant';
      final content = m['content'];
      buffer.writeln('<|$role|>\n$content</s>');
    }
    buffer.write('<|assistant|>\n');

    try {
      await _ensureContext();
      if (_contextId == null) {
        return '{"answer": "Failed to initialise model context"}';
      }

      final completionResult = await Fllama.instance()
          ?.completion(
            _contextId!,
            prompt: buffer.toString(),
            nPredict: maxTokens,
          )
          .timeout(
            const Duration(seconds: 120),
            onTimeout: () => throw TimeoutException('Model timed out'),
          );

      final text = completionResult?['text'] as String?;
      if (text != null && text.isNotEmpty) return text;
      return '{"answer": "No output"}';
    } catch (e, st) {
      debugPrint('[fllama] Error during completion: $e\n$st');
      return '{"answer": "Error interacting with fllama: $e"}';
    }
  }

  /// Expose model loading for callers.
  Future<void> loadModel() async {
    await _ensureContext();
  }

  /// Release native resources.
  Future<void> dispose() async {
    if (_contextId != null) {
      await Fllama.instance()?.releaseContext(_contextId!);
      _contextId = null;
    }
  }
}
