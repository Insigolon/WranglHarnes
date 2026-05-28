import 'package:wrangl_native/wrangl_native.dart';

class SmsReaderService {
  Future<List<Map<String, dynamic>>> readRecent({int limit = 20}) async {
    try {
      return await WranglNative.readSms(limit: limit);
    } catch (e) {
      throw Exception('Failed to read SMS: $e');
    }
  }
}
