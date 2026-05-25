import '../skills/skill_loader.dart';
import 'agent_loop.dart';
import 'memory.dart';
import 'model.dart';
import 'router.dart';
import 'skill.dart';

/// Top-level entry point for one user message: route to a skill, load its
/// memory, run the loop, persist the outcome, return the reply text.
///
/// Skills come from `assets/skills/<name>/skill.md` via [loadBundledSkills];
/// the harness itself never knows the concrete skill list at compile time.
class WranglHarness {
  final ModelComplete model;
  final List<Skill> skills;
  final Skill _fallback;
  final SkillRouter _router;

  WranglHarness._(this.model, this.skills, this._fallback)
      : _router = SkillRouter(model);

  static Future<WranglHarness> load(ModelComplete model) async {
    final skills = await loadBundledSkills();
    final fallback = skills.firstWhere(
      (s) => s.name == kFallbackSkillName,
      orElse: () => skills.first,
    );
    return WranglHarness._(model, skills, fallback);
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
