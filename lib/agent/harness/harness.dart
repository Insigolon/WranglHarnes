import '../skills/apps_skill.dart';
import '../skills/chat_skill.dart';
import '../skills/screen_skill.dart';
import 'agent_loop.dart';
import 'memory.dart';
import 'model.dart';
import 'router.dart';
import 'skill.dart';

/// Top-level entry point for one user message: route to a skill, load its
/// memory, run the loop, persist the outcome, return the reply text.
class WranglHarness {
  final ModelComplete model;
  late final List<Skill> skills;
  late final Skill _fallback;
  late final SkillRouter _router;

  WranglHarness(this.model) {
    _fallback = ChatSkill();
    skills = [_fallback, AppsSkill(), ScreenSkill()];
    _router = SkillRouter(model);
  }

  Future<String> handle(
    String task, {
    List<Map<String, dynamic>> priorTurns = const [],
  }) async {
    final skill = await _router.route(task, skills, _fallback);

    final memory = SkillMemory(skill.name);
    await memory.load();

    final loop = AgentLoop(
      model: model,
      skill: skill,
      memoryContext: memory.asContext(),
    );
    final result = await loop.run(task, priorTurns: priorTurns);

    if (result.status == LoopStatus.ok) {
      await memory.add(task, result.text);
    }
    return result.text;
  }
}
