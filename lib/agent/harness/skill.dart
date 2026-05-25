import 'tool.dart';

/// A self-contained capability. In Dart these are compiled-in objects (not
/// filesystem dirs), but the contract mirrors the skill model: a routing
/// description, a short system prompt, and a scoped tool set (<= 5).
abstract class Skill {
  /// snake_case identifier used by the router.
  String get name;

  /// <= 30 words; the only thing the router sees.
  String get description;

  /// The skill's system prompt (keep under ~500 tokens for a 2B model).
  String get instructions;

  /// Scoped tools — never the global set.
  List<ToolSpec> get tools;
}
