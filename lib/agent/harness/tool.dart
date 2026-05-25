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

  const ToolSpec({
    required this.name,
    required this.description,
    required this.run,
  });
}
