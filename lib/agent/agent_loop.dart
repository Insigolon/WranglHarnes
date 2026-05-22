import 'dart:async';
import 'dart:convert';
import 'fllama_client.dart';

class ParseResult {
  final String type; // 'tool_call', 'final_answer', 'unknown'
  final String? tool;
  final Map<String, dynamic>? args;
  final String? content;

  ParseResult({required this.type, this.tool, this.args, this.content});
}

ParseResult parseOutput(String raw) {
  var cleaned = raw.replaceAll(RegExp(r'```(?:json|tool_call)?\n?'), '').trim();
  if (cleaned.endsWith('`')) {
    cleaned = cleaned.substring(0, cleaned.length - 1).trim();
  }

  try {
    final obj = jsonDecode(cleaned) as Map<String, dynamic>;
    if (obj.containsKey('tool')) {
      return ParseResult(
        type: 'tool_call',
        tool: obj['tool'] as String?,
        args: obj['args'] as Map<String, dynamic>? ?? {},
      );
    }
    if (obj.containsKey('answer') || obj.containsKey('result')) {
      return ParseResult(
        type: 'final_answer',
        content: obj['answer'] as String? ?? obj['result'] as String?,
      );
    }
  } catch (_) {}

  // Regex fallback
  final toolMatch = RegExp(r'"tool"\s*:\s*"(\w+)"').firstMatch(cleaned);
  if (toolMatch != null) {
    final argsMatch = RegExp(
      r'"args"\s*:\s*(\{.*?\})',
      dotAll: true,
    ).firstMatch(cleaned);
    Map<String, dynamic> args = {};
    if (argsMatch != null) {
      try {
        args = jsonDecode(argsMatch.group(1)!) as Map<String, dynamic>;
      } catch (_) {}
    }
    return ParseResult(type: 'tool_call', tool: toolMatch.group(1), args: args);
  }

  return ParseResult(type: 'final_answer', content: raw.trim());
}

Future<String> sandboxExec(
  Map<String, Function> tools,
  ParseResult parsed, {
  int timeoutS = 10,
}) async {
  final fn = tools[parsed.tool];
  if (fn == null) return "ERROR: unknown tool '${parsed.tool}'";

  try {
    // We assume the tool takes a single Map<String, dynamic> of kwargs
    final result = await Future(
      () => fn(parsed.args),
    ).timeout(Duration(seconds: timeoutS));
    final strResult = result.toString();
    return strResult.length > 500 ? strResult.substring(0, 500) : strResult;
  } on TimeoutException {
    return "ERROR: tool '${parsed.tool}' timed out after ${timeoutS}s";
  } catch (e) {
    return "ERROR: ${e.runtimeType}: $e";
  }
}

class EvalResult {
  final bool passed;
  final double score;
  final String reason;
  final String retryPrompt;

  EvalResult(this.passed, this.score, this.reason, this.retryPrompt);
}

abstract class LoopCheck {
  EvalResult run(
    String task,
    String output,
    List<Map<String, dynamic>> history,
  );
}

class LoopEvaluator {
  final List<LoopCheck> checks;
  LoopEvaluator(this.checks);

  EvalResult evaluate(
    String task,
    String output,
    List<Map<String, dynamic>> history,
  ) {
    final results = checks.map((c) => c.run(task, output, history)).toList();
    final score =
        results.fold<double>(0.0, (sum, r) => sum + r.score) /
        (results.isEmpty ? 1 : results.length);
    final failures = results.where((r) => !r.passed).toList();

    if (failures.isEmpty) {
      return EvalResult(true, score, "all checks passed", "");
    }

    final retry =
        "Your previous response had issues:\n" +
        failures.map((f) => "  - ${f.reason}").join("\n") +
        "\nPlease try again addressing each issue.";

    return EvalResult(
      false,
      score,
      failures.map((f) => f.reason).join("; "),
      retry,
    );
  }
}

class FormatCheck implements LoopCheck {
  @override
  EvalResult run(
    String task,
    String output,
    List<Map<String, dynamic>> history,
  ) {
    final parsed = parseOutput(output);
    final ok = parsed.type != 'unknown';
    return EvalResult(
      ok,
      ok ? 1.0 : 0.0,
      ok ? "" : "Output could not be parsed",
      "",
    );
  }
}

class LoopDetector implements LoopCheck {
  @override
  EvalResult run(
    String task,
    String output,
    List<Map<String, dynamic>> history,
  ) {
    final msgs = history
        .where((m) => m['role'] == 'assistant')
        .map((m) => m['content'] as String)
        .toList();
    if (msgs.length >= 2 && msgs.last == msgs[msgs.length - 2]) {
      return EvalResult(
        false,
        0.0,
        "Agent stuck — identical consecutive outputs",
        "Your last two responses were identical. Try a completely different approach.",
      );
    }
    return EvalResult(true, 1.0, "", "");
  }
}

class ToolHallucinationCheck implements LoopCheck {
  final List<String> validTools;
  ToolHallucinationCheck(this.validTools);

  @override
  EvalResult run(
    String task,
    String output,
    List<Map<String, dynamic>> history,
  ) {
    final parsed = parseOutput(output);
    if (parsed.type == 'tool_call' && !validTools.contains(parsed.tool)) {
      return EvalResult(
        false,
        0.0,
        "Model called non-existent tool '${parsed.tool}'",
        "Available tools are: $validTools. Use ONLY these exact names.",
      );
    }
    return EvalResult(true, 1.0, "", "");
  }
}

class AgentLoop {
  final FLlamaModelClient modelClient;
  final Map<String, Function> tools;
  final LoopEvaluator evaluator;
  final String systemPrompt;
  final int maxIterations;
  final int maxRetries;

  AgentLoop({
    required this.modelClient,
    required this.tools,
    required this.evaluator,
    required this.systemPrompt,
    this.maxIterations = 10,
    this.maxRetries = 3,
  });

  Future<Map<String, dynamic>> runTask(String task) async {
    final history = <Map<String, dynamic>>[
      {'role': 'user', 'content': task},
    ];
    int retries = 0;

    for (int iteration = 0; iteration < maxIterations; iteration++) {
      final raw = await modelClient.complete(
        systemPrompt,
        history,
        tools: tools.keys.toList(),
      );
      final parsed = parseOutput(raw);

      if (parsed.type == 'tool_call') {
        final result = await sandboxExec(tools, parsed);
        history.add({'role': 'assistant', 'content': raw});
        history.add({'role': 'tool', 'content': result});
        continue;
      }

      if (parsed.type == 'final_answer') {
        final evalResult = evaluator.evaluate(
          task,
          parsed.content ?? '',
          history,
        );
        if (evalResult.passed) {
          return {
            'status': 'ok',
            'result': parsed.content,
            'iterations': iteration + 1,
            'skill_used': null, // filled by caller
          };
        }
        if (retries < maxRetries) {
          retries++;
          history.add({'role': 'user', 'content': evalResult.retryPrompt});
          continue;
        }
        return {
          'status': 'partial',
          'result': parsed.content,
          'reason': evalResult.reason,
        };
      }
    }

    return {'status': 'max_iterations', 'result': null, 'history': history};
  }
}
