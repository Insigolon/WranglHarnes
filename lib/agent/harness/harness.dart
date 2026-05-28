import 'dart:typed_data';

import '../../core/agent/tool_registry.dart';
import 'agent_loop.dart';
import 'model.dart';
import 'tool.dart';

class WranglHarness {
  final ModelComplete model;
  final List<ToolSpec> tools;

  WranglHarness._(this.model, this.tools);

  static WranglHarness load(ModelComplete model) {
    setModelForTools(model);
    return WranglHarness._(model, kToolRegistry.values.toList());
  }

  Future<String> handle(
    String task, {
    Uint8List? image,
    List<Map<String, dynamic>> priorTurns = const [],
    StepCallback? onStep,
    CancellationToken? cancelToken,
  }) async {
    final loop = AgentLoop(
      model: model,
      tools: tools,
      systemPrompt: _buildSystemPrompt(),
      maxIterations: 10,
      onStep: onStep,
      cancelToken: cancelToken,
    );
    final result = await loop.run(
      task,
      initialImage: image,
      priorTurns: priorTurns,
    );
    return result.text;
  }

  String _buildSystemPrompt() {
    final b = StringBuffer(
      'You are Wrangl, a helpful on-device assistant running on the user\'s phone. '
      'Answer the user directly and concisely.\n'
      'Before answering, reason step-by-step inside <think>...</think> tags.\n\n',
    );
    if (tools.isNotEmpty) {
      b.writeln('To use a tool, reply with ONLY a JSON object:');
      b.writeln('{"tool": "<name>", "args": { ... }}');
      b.writeln('\nAvailable tools:');
      for (final t in tools) {
        b.writeln('- ${t.name}: ${t.description}');
      }
      b.writeln('\nWhen you have the final reply, respond with ONLY:');
      b.writeln('{"answer": "<text>"}');
    }
    return b.toString();
  }
}
