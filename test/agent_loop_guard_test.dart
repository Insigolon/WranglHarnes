import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wranglv0/agent/harness/agent_loop.dart';
import 'package:wranglv0/src/rust/api/harness.dart' as rust;

rust.StepDecision _finalDecision({
  required String rawModelOutput,
  required List<String> validTools,
  required List<String> prevAssistantOutputs,
  required int retriesSoFar,
  required int maxRetries,
}) {
  var finalText = rawModelOutput;
  try {
    final decoded = jsonDecode(rawModelOutput);
    if (decoded is Map && decoded['answer'] is String) {
      finalText = decoded['answer'] as String;
    }
  } catch (_) {}
  return rust.StepDecision(
    action: rust.DecisionAction.emitFinal,
    finalText: finalText,
    newAssistantLog: rawModelOutput,
    retriesAfter: retriesSoFar,
  );
}

AgentLoop _loop(List<String> responses) {
  return AgentLoop(
    tools: const [],
    systemPrompt: 'Answer naturally.',
    decideNext: _finalDecision,
    model:
        ({
          required String system,
          required List<Map<String, dynamic>> history,
          Uint8List? image,
          int maxTokens = 512,
        }) async => responses.removeAt(0),
  );
}

void main() {
  test('emits final answer when it passes evaluation', () async {
    final result =
        await _loop(['{"answer":"Hello."}']).run('hi');

    expect(result.status, LoopStatus.ok);
    expect(result.text, 'Hello.');
  });

  test('allows plain-text final answers', () async {
    final result = await _loop(['Hello.']).run('hi');

    expect(result.status, LoopStatus.ok);
    expect(result.text, 'Hello.');
  });
}
