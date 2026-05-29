import 'package:wrangl_native/wrangl_native.dart';

class LauncherService {
  Future<List<Map<String, dynamic>>> getInstalledApps() async {
    return WranglNative.getInstalledApps();
  }

  Future<bool> openApp(String packageName) async {
    return WranglNative.launchApp(packageName);
  }
}
