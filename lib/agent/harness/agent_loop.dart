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

/// The inner agent loop for one skill. Orchestrates the Dart model + tools, but
/// delegates the brittle bits — output parsing and the eval gate — to the Rust
/// core ([rust.parseOutput] / [rust.evaluate]).
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
      final parsed = rust.parseOutput(raw: raw);

      if (parsed.kind == rust.ParsedKind.toolCall) {
        final ev = rust.evaluate(
          outputRaw: raw,
          validTools: validTools,
          prevAssistantOutputs: assistantOutputs,
        );
        assistantOutputs.add(raw);
        history.add({'role': 'assistant', 'content': raw});
        if (!ev.passed) {
          if (retries < maxRetries) {
            retries++;
            history.add({'role': 'user', 'content': ev.retryPrompt});
            continue;
          }
          return LoopResult(
              LoopStatus.partial, 'I could not complete that: ${ev.reason}');
        }

        var args = <String, dynamic>{};
        final aj = parsed.argsJson;
        if (aj != null) {
          try {
            final d = jsonDecode(aj);
            if (d is Map) args = d.cast<String, dynamic>();
          } catch (_) {}
        }

        final result = await runTool(skill.tools, parsed.tool!, args);
        if (result.kind == ToolResultKind.image && result.image != null) {
          history.add({
            'role': 'tool',
            'content': 'Screenshot captured. Use it to answer the user.'
          });
          pendingImage = result.image; // attaches to the next model turn
        } else {
          history.add({'role': 'tool', 'content': result.text});
        }
        continue;
      }

      // Final answer.
      final ev = rust.evaluate(
        outputRaw: raw,
        validTools: validTools,
        prevAssistantOutputs: assistantOutputs,
      );
      assistantOutputs.add(raw);
      final content = parsed.content ?? raw;
      if (ev.passed) return LoopResult(LoopStatus.ok, content);
      if (retries < maxRetries) {
        retries++;
        history.add({'role': 'assistant', 'content': raw});
        history.add({'role': 'user', 'content': ev.retryPrompt});
        continue;
      }
      return LoopResult(LoopStatus.partial, content);
    }
    return LoopResult(
        LoopStatus.maxIterations, "I'm having trouble — try rephrasing that.");
  }
}
