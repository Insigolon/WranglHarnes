import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../../src/rust/api/harness.dart' as rust;
import 'model.dart';
import 'sandbox.dart';
import 'skill.dart';
import 'tool.dart';

enum LoopStatus { ok, partial, maxIterations }

class LoopResult {
  final LoopStatus status;
  final String text;
  LoopResult(this.status, this.text);
}

/// The inner agent loop for one skill.
///
/// All branching logic — parse model output, evaluate it, decide whether to
/// call a tool, retry, finalize, or give up — lives in Rust as
/// `decide_next`. Dart's job is just to (a) run the Gemma model, (b) execute
/// tools (which are Flutter plugin calls and so have to be Dart), and
/// (c) thread history through.
class AgentLoop {
  final ModelComplete model;
  final Skill skill;
  final String memoryContext;
  final int maxIterations;
  final int maxRetries;

  AgentLoop({
    required this.model,
    required this.skill,
    this.memoryContext = '',
    this.maxIterations = 8,
    this.maxRetries = 3,
  });

  String _systemPrompt() {
    final b = StringBuffer(skill.instructions);
    if (skill.tools.isNotEmpty) {
      b.writeln('\n\nTo use a tool, reply with ONLY a JSON object:');
      b.writeln('{"tool": "<name>", "args": { ... }}');
      b.writeln('Tools:');
      for (final t in skill.tools) {
        b.writeln('- ${t.name}: ${t.description}');
      }
      b.writeln('When you have the final reply, respond with ONLY:');
      b.writeln('{"answer": "<text>"}');
    }
    if (memoryContext.isNotEmpty) {
      b.writeln('\nRelevant memory:\n$memoryContext');
    }
    return b.toString();
  }

  Future<LoopResult> run(
    String task, {
    Uint8List? initialImage,
    List<Map<String, dynamic>> priorTurns = const [],
  }) async {
    final history = <Map<String, dynamic>>[
      ...priorTurns,
      {'role': 'user', 'content': task}
    ];
    final assistantOutputs = <String>[];
    final validTools = skill.tools.map((t) => t.name).toList();
    final system = _systemPrompt();
    var retries = 0;
    Uint8List? pendingImage = initialImage;

    for (var i = 0; i < maxIterations; i++) {
      final raw = await model(
        system: system,
        history: history,
        image: pendingImage,
        maxTokens: 512,
      );
      pendingImage = null;

      final d = rust.decideNext(
        rawModelOutput: raw,
        validTools: validTools,
        prevAssistantOutputs: assistantOutputs,
        retriesSoFar: retries,
        maxRetries: maxRetries,
      );
      retries = d.retriesAfter;

      if (d.newAssistantLog.isNotEmpty) {
        assistantOutputs.add(d.newAssistantLog);
        history.add({'role': 'assistant', 'content': d.newAssistantLog});
      }

      switch (d.action) {
        case rust.DecisionAction.emitFinal:
          return LoopResult(LoopStatus.ok, d.finalText ?? raw);

        case rust.DecisionAction.aborted:
          return LoopResult(LoopStatus.partial, d.finalText ?? raw);

        case rust.DecisionAction.retry:
          if (d.retryFeedback != null && d.retryFeedback!.isNotEmpty) {
            history.add({'role': 'user', 'content': d.retryFeedback});
          }
          continue;

        case rust.DecisionAction.callTool:
          final args = _decodeArgs(d.toolArgsJson);
          final result = await runTool(skill.tools, d.toolName!, args);
          if (result.kind == ToolResultKind.image && result.image != null) {
            history.add({
              'role': 'tool',
              'content': 'Screenshot captured. Use it to answer the user.'
            });
            pendingImage = result.image;
          } else {
            history.add({'role': 'tool', 'content': result.text});
          }
          continue;
      }
    }
    return LoopResult(
        LoopStatus.maxIterations, "I'm having trouble — try rephrasing that.");
  }

  Map<String, dynamic> _decodeArgs(String? argsJson) {
    if (argsJson == null || argsJson.isEmpty) return const {};
    try {
      final d = jsonDecode(argsJson);
      if (d is Map) return d.cast<String, dynamic>();
    } catch (_) {}
    return const {};
  }
}
