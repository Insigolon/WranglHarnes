import 'package:flutter/services.dart' show rootBundle;

import '../harness/skill.dart';
import '../harness/tool.dart';
import 'tool_registry.dart';

/// Names of the bundled skill.md assets. Adding a skill = drop a new
/// `assets/skills/<name>/skill.md`, register its tools in [kToolRegistry],
/// add the asset to pubspec, and append the name here.
const List<String> kBundledSkillNames = ['chat', 'apps', 'screen'];

/// The fallback skill used when routing returns "none" or fails.
const String kFallbackSkillName = 'chat';

/// Load every bundled skill from its asset, resolving tool names against
/// [kToolRegistry]. Throws if a `.md` references a tool name that isn't
/// registered — that's a programmer error, not a runtime condition.
Future<List<Skill>> loadBundledSkills() async {
  final out = <Skill>[];
  for (final name in kBundledSkillNames) {
    out.add(await _loadSkill(name));
  }
  return out;
}

Future<Skill> _loadSkill(String dirName) async {
  final raw = await rootBundle.loadString('assets/skills/$dirName/skill.md');
  final parsed = _parseSkillMd(raw);
  final tools = <ToolSpec>[];
  for (final toolName in parsed.toolNames) {
    final spec = kToolRegistry[toolName];
    if (spec == null) {
      throw StateError(
        'skill "$dirName" references unknown tool "$toolName" — '
        'add it to kToolRegistry or fix the skill.md',
      );
    }
    tools.add(spec);
  }
  return Skill(
    name: parsed.name,
    description: parsed.description,
    instructions: parsed.instructions,
    tools: tools,
  );
}

class _ParsedSkillMd {
  final String name;
  final String description;
  final String instructions;
  final List<String> toolNames;
  _ParsedSkillMd(
      this.name, this.description, this.instructions, this.toolNames);
}

/// Minimal YAML-frontmatter parser for our own files — we own the format, so
/// we don't need a real YAML parser. Expects:
///
///   ---
///   name: `<slug>`
///   description: `<one line>`
///   tools: [a, b, c]        # or [] for none
///   ---
///   `<body = system prompt>`
_ParsedSkillMd _parseSkillMd(String raw) {
  final text = raw.replaceAll('\r\n', '\n').trim();
  if (!text.startsWith('---')) {
    throw FormatException('skill.md must start with --- frontmatter');
  }
  final after = text.substring(3);
  final end = after.indexOf('\n---');
  if (end < 0) {
    throw FormatException('skill.md frontmatter is not closed with ---');
  }
  final front = after.substring(0, end).trim();
  final body = after.substring(end + 4).trim(); // skip "\n---"

  String? name;
  String? description;
  List<String> tools = const [];

  for (final line in front.split('\n')) {
    final colon = line.indexOf(':');
    if (colon < 0) continue;
    final key = line.substring(0, colon).trim();
    final value = line.substring(colon + 1).trim();
    switch (key) {
      case 'name':
        name = value;
        break;
      case 'description':
        description = value;
        break;
      case 'tools':
        tools = _parseInlineList(value);
        break;
    }
  }

  if (name == null || name.isEmpty) {
    throw FormatException('skill.md missing "name"');
  }
  if (description == null || description.isEmpty) {
    throw FormatException('skill.md missing "description"');
  }
  return _ParsedSkillMd(name, description, body, tools);
}

List<String> _parseInlineList(String raw) {
  var s = raw.trim();
  if (!s.startsWith('[') || !s.endsWith(']')) return const [];
  s = s.substring(1, s.length - 1).trim();
  if (s.isEmpty) return const [];
  return s
      .split(',')
      .map((e) => e.trim().replaceAll('"', '').replaceAll("'", ''))
      .where((e) => e.isNotEmpty)
      .toList();
}
