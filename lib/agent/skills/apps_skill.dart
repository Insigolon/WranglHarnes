import 'package:wrangl_native/wrangl_native.dart';

import '../harness/skill.dart';
import '../harness/tool.dart';

/// Find and open installed apps. Tools call the native plugin, which works from
/// the overlay isolate because the plugin auto-registers on every engine.
class AppsSkill extends Skill {
  @override
  String get name => 'apps';

  @override
  String get description => 'Open or launch installed apps on the phone.';

  @override
  String get instructions =>
      'You help the user open apps. First call list_apps to find the exact '
      'package name, then call open_app with it. Then confirm in one short line.';

  @override
  List<ToolSpec> get tools => [
        ToolSpec(
          name: 'list_apps',
          description: 'List installed apps as "label (package)". args: {}',
          run: (_) async {
            final apps = await WranglNative.getInstalledApps();
            return ToolResult.text(
              apps.map((a) => '${a['label']} (${a['packageName']})').join('; '),
            );
          },
        ),
        ToolSpec(
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
      ];
}
