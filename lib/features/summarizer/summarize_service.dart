import '../../agent/harness/model.dart';

class SummarizeService {
  final ModelComplete _complete;

  SummarizeService(this._complete);

  Future<String> summarize(String text) async {
    final prompt =
        'Summarize the following document into concise bullet points:\n\n$text';
    return _complete(
      system: '',
      history: [
        {'role': 'user', 'content': prompt},
      ],
      maxTokens: 512,
    );
  }
}
