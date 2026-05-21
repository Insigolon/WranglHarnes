import 'package:fllama/fllama.dart';

class FLlamaModelClient {
  final String modelPath;

  FLlamaModelClient(this.modelPath);

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
          tools.map((t) => '  - \$t').join('\n') +
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
      final initResult = await Fllama.instance()?.initContext(modelPath);
      if (initResult == null) return '{"answer": "Failed to init context"}';

      final contextId = initResult['contextId'] as double? ?? 0.0;
      final completionResult = await Fllama.instance()?.completion(
        contextId,
        prompt: buffer.toString(),
        nPredict: maxTokens,
      );

      await Fllama.instance()?.releaseContext(contextId);

      return completionResult?['text'] as String? ?? '{"answer": "No output"}';
    } catch (e) {
      return '{"answer": "Error interacting with fllama: \$e"}';
    }
  }
}
