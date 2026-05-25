import 'tool.dart';

/// A self-contained capability loaded from a `skill.md` asset. Everything here
/// (name, description, instructions) comes from the markdown file; only the
/// tool implementations are resolved in code, by name, from the tool registry.
class Skill {
  /// snake_case identifier used by the router.
  final String name;

  /// <= 30 words; the only thing the router sees.
  final String description;

  /// The skill's system prompt (keep under ~500 tokens for a 2B model).
  final String instructions;

  /// Scoped tools — never the global set.
  final List<ToolSpec> tools;

  const Skill({
    required this.name,
    required this.description,
    required this.instructions,
    required this.tools,
  });
}
