import '../harness/skill.dart';
import '../harness/tool.dart';

/// Default fallback skill — plain conversation, no tools.
class ChatSkill extends Skill {
  @override
  String get name => 'chat';

  @override
  String get description =>
      'General conversation, questions, writing, and explanations.';

  @override
  String get instructions =>
      'You are Wrangl, a concise and helpful on-device assistant. Answer the '
      'user directly and briefly.';

  @override
  List<ToolSpec> get tools => const [];
}
