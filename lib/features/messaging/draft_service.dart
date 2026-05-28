import '../../agent/harness/model.dart';

class DraftService {
  final ModelComplete _complete;

  DraftService(this._complete);

  Future<String> generateDraft(String context, String tone) async {
    final prompt =
        'Draft a $tone email/message given this context: $context\nOutput only the draft text.';
    return _complete(
      system: '',
      history: [
        {'role': 'user', 'content': prompt},
      ],
      maxTokens: 512,
    );
  }
}
