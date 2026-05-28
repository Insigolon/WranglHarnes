import 'dart:typed_data';

import '../../agent/harness/model.dart';

class OcrEngine {
  final ModelComplete _complete;

  OcrEngine(this._complete);

  Future<String> extractText(Uint8List image) async {
    return _complete(
      system: '',
      history: [
        {
          'role': 'user',
          'content': 'Extract all visible text from this image verbatim.',
        },
      ],
      image: image,
      maxTokens: 512,
    );
  }
}
