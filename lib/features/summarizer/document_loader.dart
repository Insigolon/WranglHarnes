import 'dart:io';

class DocumentLoader {
  static const int maxChars = 4000;

  Future<String> loadText(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('File not found: $filePath');
    }

    final ext = filePath.split('.').last.toLowerCase();
    if (!['txt', 'md', 'csv', 'log', 'json', 'xml', 'yaml', 'yml']
        .contains(ext)) {
      throw Exception('Unsupported file type: .$ext');
    }

    final bytes = await file.readAsBytes();
    final text = String.fromCharCodes(bytes);

    if (text.length <= maxChars) return text;
    return text.substring(0, maxChars);
  }
}
