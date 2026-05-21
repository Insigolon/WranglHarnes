import 'skill.dart';
import 'fllama_client.dart';

class SkillRouter {
  final List<Skill> registry;

  SkillRouter(this.registry);

  Future<Skill?> routeSkill(String task, FLlamaModelClient client) async {
    final registryText = registry
        .map((s) => '- ${s.name}: ${s.description}')
        .join('\n');
    final prompt =
        'Available skills:\n$registryText\n\n'
        'Task: $task\n\n'
        'Reply with ONLY the skill name that best matches this task. '
        "If no skill fits, reply 'none'.";

    final raw = await client.complete(
      'You are a skill router. Reply with a single skill name only. No explanation.',
      [
        {'role': 'user', 'content': prompt},
      ],
      maxTokens: 50,
    );

    final chosen = raw.trim().toLowerCase().split(RegExp(r'\s+')).first;
    var match = _findSkill(chosen);

    if (match == null) {
      // Retry once with a stricter hint
      final raw2 = await client.complete(
        'You are a skill router. Reply with a single skill name only. No explanation.',
        [
          {
            'role': 'user',
            'content':
                'Task: $task\n'
                'You MUST reply with one of: ${registry.map((s) => s.name).toList()}\n'
                'Reply with the single best matching name.',
          },
        ],
        maxTokens: 50,
      );
      final chosen2 = raw2.trim().toLowerCase().split(RegExp(r'\s+')).first;
      match = _findSkill(chosen2);
    }

    return match;
  }

  Skill? _findSkill(String name) {
    try {
      return registry.firstWhere((s) => s.name == name);
    } catch (_) {
      return null;
    }
  }
}
