abstract class Skill {
  String get name;
  String get description;
  String get systemPrompt;
  Map<String, Function> get tools;
}

class ChatSkill implements Skill {
  @override
  String get name => 'chat';

  @override
  String get description =>
      'General Q&A and conversation. Use this skill when no other skill matches the request.';

  @override
  String get systemPrompt =>
      'You are a helpful AI assistant. Answer the user\'s request to the best of your ability.';

  @override
  Map<String, Function> get tools => {};
}
