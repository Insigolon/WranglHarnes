import 'dart:async';
import 'tool.dart';

/// Run a tool call defensively: resolve the name, enforce a timeout, truncate
/// text output, and turn every failure into an `ERROR:` string that re-enters
/// the loop rather than throwing.
Future<ToolResult> runTool(
  List<ToolSpec> tools,
  String name,
  Map<String, dynamic> args, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  ToolSpec? spec;
  for (final t in tools) {
    if (t.name == name) {
      spec = t;
      break;
    }
  }
  if (spec == null) return ToolResult.text("ERROR: unknown tool '$name'");

  try {
    final r = await spec.run(args).timeout(timeout);
    if (r.kind == ToolResultKind.text && r.text.length > 500) {
      return ToolResult.text(r.text.substring(0, 500));
    }
    return r;
  } on TimeoutException {
    return ToolResult.text("ERROR: tool '$name' timed out");
  } catch (e) {
    return ToolResult.text('ERROR: $e');
  }
}
