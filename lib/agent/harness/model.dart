import 'dart:typed_data';

/// The harness depends only on this closure, not on flutter_gemma directly, so
/// the loop and router stay decoupled and testable. The last entry in
/// [history] is the current user turn; [image] (when set) attaches to it.
typedef ModelComplete = Future<String> Function({
  required String system,
  required List<Map<String, dynamic>> history,
  Uint8List? image,
  int maxTokens,
});
