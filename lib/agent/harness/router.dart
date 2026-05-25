import '../../src/rust/api/harness.dart' as rust;
import 'model.dart';
import 'skill.dart';

/// Hybrid router: the Rust deterministic fast-path first, then a single
/// constrained LLM classification only when that returns "none".
class SkillRouter {
  final ModelComplete model;
  SkillRouter(this.model);

  Future<Skill> route(String task, List<Skill> skills, Skill fallback) async {
    final descs = skills
        .map((s) => rust.SkillDesc(name: s.name, description: s.description))
        .toList();

    final fast = rust.routeSkill(task: task, skills: descs);
    if (fast != 'none') {
      for (final s in skills) {
        if (s.name == fast) return s;
      }
    }

    // LLM fallback — keep it cheap and tightly constrained.
    final names = skills.map((s) => s.name).join(', ');
    final list =
        skills.map((s) => '- ${s.name}: ${s.description}').join('\n');
    try {
      final raw = await model(
        system:
            'You are a skill router. Reply with exactly one skill name, nothing else.',
        history: [
          {
            'role': 'user',
            'content':
                'Skills:\n$list\n\nUser: $task\n\nReply with ONE of: $names'
          }
        ],
        maxTokens: 12,
      );
      final pick = raw.trim().toLowerCase();
      for (final s in skills) {
        if (pick.contains(s.name)) return s;
      }
    } catch (_) {}

    return fallback;
  }
}
