import 'package:wrangl_native/wrangl_native.dart';

import '../harness/tool.dart';

/// Every tool the agent can call, keyed by the snake_case name that appears
/// in a skill.md `tools:` list. The skill loader pulls the implementations
/// from here; the `.md` file decides which subset each skill exposes.
///
/// Tool implementations have to live in Dart (they call platform plugins);
/// the `.md` files own descriptions and routing/system-prompt text.
final Map<String, ToolSpec> kToolRegistry = {
  'list_apps': ToolSpec(
    name: 'list_apps',
    description: 'List installed apps as "label (package)". args: {}',
    run: (_) async {
      final apps = await WranglNative.getInstalledApps();
      return ToolResult.text(
        apps.map((a) => '${a['label']} (${a['packageName']})').join('; '),
      );
    },
  ),
  'open_app': ToolSpec(
    name: 'open_app',
    description: 'Open an app. args: {"package": "com.example.app"}',
    run: (args) async {
      final pkg = args['package']?.toString() ?? '';
      if (pkg.isEmpty) return ToolResult.text('ERROR: missing "package"');
      final ok = await WranglNative.launchApp(pkg);
      return ToolResult.text(
          ok ? 'Opened $pkg' : 'ERROR: could not open $pkg');
    },
  ),
  'capture_screen': ToolSpec(
    name: 'capture_screen',
    description: 'Take a screenshot of the current screen. args: {}',
    run: (_) async {
      if (!await WranglNative.isScreenReady()) {
        return ToolResult.text(
          'ERROR: screen capture is not available right now. '
          'Open Wrangl and accept the screen-capture prompt, then try again.',
        );
      }
      final bytes = await WranglNative.captureScreen();
      if (bytes == null) {
        return ToolResult.text('ERROR: could not capture the screen.');
      }
      return ToolResult.image(bytes);
    },
  ),
};
