import 'package:wrangl_native/wrangl_native.dart';

import '../../agent/harness/tool.dart';
import 'web_search.dart';

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
        ok ? 'Opened $pkg' : 'ERROR: could not open $pkg',
      );
    },
  ),
  'web_search': ToolSpec(
    name: 'web_search',
    description:
        'Search the web for information. args: {"query": "search query here"}',
    run: (args) async {
      final query = args['query']?.toString() ?? '';
      if (query.isEmpty) return ToolResult.text('ERROR: missing "query"');
      final results = await WebSearch.search(query);
      return ToolResult.text(results);
    },
  ),
  'capture_screen': ToolSpec(
    name: 'capture_screen',
    description: 'Capture the current screen contents. args: {}',
    run: (_) async {
      final image = await WranglNative.captureScreen();
      return ToolResult.image(image);
    },
  ),
};
