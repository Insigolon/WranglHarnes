import 'package:wrangl_native/wrangl_native.dart';

class FileIndexService {
  Future<List<Map<String, dynamic>>> search(String query) async {
    final results = await WranglNative.scanFiles(query: query);
    return results;
  }

  Future<List<Map<String, dynamic>>> searchByType(String mimeType) async {
    final results = await WranglNative.scanFiles(mimeType: mimeType);
    return results;
  }
}
