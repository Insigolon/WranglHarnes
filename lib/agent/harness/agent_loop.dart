import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../../src/rust/api/harness.dart' as rust;
import 'model.dart';
import 'sandbox.dart';
import 'tool.dart';

enum LoopStatus { ok, partial, maxIterations }

class LoopResult {
  final LoopStatus status;
  final String text;
  LoopResult(this.status, this.text);
}

typedef DecideNextFn = rust.StepDecision Function({
  required String rawModelOutput,
  required List<String> validTools,
  required List<String> prevAssistantOutputs,
  required int retriesSoFar,
  required int maxRetries,
});

typedef StepCallback = void Function(AgentStep step);

class AgentLoop {
  final ModelComplete model;
  final List<ToolSpec> tools;
  final String systemPrompt;
  final int maxIterations;
  final int maxRetries;
  final DecideNextFn decideNext;
  final StepCallback? onStep;
  final CancellationToken cancelToken;

  AgentLoop({
    required this.model,
    required this.tools,
    required this.systemPrompt,
    this.maxIterations = 8,
    this.maxRetries = 3,
    DecideNextFn? decideNext,
    this.onStep,
    CancellationToken? cancelToken,
  })  : decideNext = decideNext ?? rust.decideNext,
        cancelToken = cancelToken ?? CancellationToken.none;

  Future<LoopResult> run(
    String task, {
    Uint8List? initialImage,
    List<Map<String, dynamic>> priorTurns = const [],
  }) async {
    final history = <Map<String, dynamic>>[
      ...priorTurns,
      {'role': 'user', 'content': task},
    ];
    final assistantOutputs = <String>[];
    final validTools = tools.map((t) => t.name).toList();
    var retries = 0;
    Uint8List? pendingImage = initialImage;

    for (var i = 0; i < maxIterations; i++) {
      if (cancelToken.isCancelled) {
        return LoopResult(LoopStatus.partial, 'Cancelled');
      }

      final raw = await model(
        system: systemPrompt,
        history: history,
        image: pendingImage,
        maxTokens: 512,
      );
      pendingImage = null;

      final d = decideNext(
        rawModelOutput: raw,
        validTools: validTools,
        prevAssistantOutputs: assistantOutputs,
        retriesSoFar: retries,
        maxRetries: maxRetries,
      );
      retries = d.retriesAfter;

      void logAssistantTurn() {
        if (d.newAssistantLog.isEmpty) return;
        assistantOutputs.add(d.newAssistantLog);
        history.add({'role': 'assistant', 'content': d.newAssistantLog});
      }

      switch (d.action) {
        case rust.DecisionAction.emitFinal:
          logAssistantTurn();
          return LoopResult(LoopStatus.ok, d.finalText ?? raw);

        case rust.DecisionAction.aborted:
          logAssistantTurn();
          return LoopResult(LoopStatus.partial, d.finalText ?? raw);

        case rust.DecisionAction.retry:
          logAssistantTurn();
          if (d.retryFeedback != null && d.retryFeedback!.isNotEmpty) {
            history.add({'role': 'user', 'content': d.retryFeedback});
          }
          continue;

        case rust.DecisionAction.callTool:
          logAssistantTurn();

          final toolSpec = _findTool(d.toolName);
          final step = AgentStep(
            toolName: d.toolName!,
            label: toolSpec?.stepLabel ?? d.toolName!,
            status: StepStatus.running,
            startedAt: DateTime.now(),
          );
          onStep?.call(step);

          final args = _decodeArgs(d.toolArgsJson);
          final result = await runTool(tools, d.toolName!, args);

          final resultStep = AgentStep(
            toolName: d.toolName!,
            label: toolSpec?.stepLabel ?? d.toolName!,
            status: result.text.startsWith('ERROR:')
                ? StepStatus.failed
                : StepStatus.completed,
            startedAt: step.startedAt,
          );
          onStep?.call(resultStep);

          if (result.kind == ToolResultKind.image && result.image != null) {
            history.add({
              'role': 'tool',
              'content': 'Screenshot captured. Use it to answer the user.',
            });
            pendingImage = result.image;
          } else {
            history.add({'role': 'tool', 'content': result.text});
          }
          continue;
      }
    }
    return LoopResult(
      LoopStatus.maxIterations,
      "I'm having trouble. Try rephrasing that.",
    );
  }

  ToolSpec? _findTool(String? name) {
    if (name == null) return null;
    for (final t in tools) {
      if (t.name == name) return t;
    }
    return null;
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
