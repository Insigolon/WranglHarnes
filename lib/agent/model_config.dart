import 'package:path_provider/path_provider.dart';

/// Single source of truth for where the on-device Gemma model lives.
///
/// Both the downloader (main isolate) and the overlay isolate resolve the
/// model file through here so they always agree on the path.
class ModelConfig {
  static const String fileName = 'gemma-4-E2B-it.litertlm';
  static const String displayName = 'Gemma 4 2B (~2.6 GB)';
  static const String url =
      'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm';
  /// Minimum file size (2 GB) to treat the model as fully downloaded.
  static const int minSize = 2 * 1024 * 1024 * 1024;

  static Future<String> path() async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/$fileName';
  }
}
