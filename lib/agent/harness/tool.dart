import 'dart:typed_data';

/// A tool result is either text (fed back into the transcript) or an image
/// (attached to the next model turn — bypasses the text-truncation path).
enum ToolResultKind { text, image }

class ToolResult {
  final ToolResultKind kind;
  final String text;
  final Uint8List? image;

  ToolResult.text(this.text)
      : kind = ToolResultKind.text,
        image = null;

  ToolResult.image(this.image, {this.text = '[screenshot captured]'})
      : kind = ToolResultKind.image;
}

typedef ToolFn = Future<ToolResult> Function(Map<String, dynamic> args);

/// One scoped tool: a short snake_case name, a one-line description with an
/// args example, and the function that runs it.
class ToolSpec {
  final String name;
  final String description;
  final ToolFn run;
  final String? stepLabel;

  const ToolSpec({
    required this.name,
    required this.description,
    required this.run,
    this.stepLabel,
  });
}

// ─── Agent step tracking ─────────────────────────────────────────────────────

enum StepStatus { running, completed, failed }

class AgentStep {
  final String toolName;
  final String label;
  final StepStatus status;
  final DateTime startedAt;

  const AgentStep({
    required this.toolName,
    required this.label,
    required this.status,
    required this.startedAt,
  });
}

/// A cooperative cancellation token checked by the agent loop at each
/// iteration boundary. When [isCancelled] turns true the loop breaks and
/// returns whatever partial result it has.
class CancellationToken {
  bool _cancelled = false;

  void cancel() => _cancelled = true;

  bool get isCancelled => _cancelled;

  static final CancellationToken none = CancellationToken._internal();

  CancellationToken._internal();

  CancellationToken();
}
