import 'package:wrangl_native/wrangl_native.dart';

import '../harness/skill.dart';
import '../harness/tool.dart';

/// Look at the user's current screen. capture_screen returns an image result,
/// which the loop attaches to the next model turn for the (vision) model to read.
class ScreenSkill extends Skill {
  @override
  String get name => 'screen';

  @override
  String get description =>
      "Look at what's currently on the user's screen and answer about it.";

  @override
  String get instructions =>
      'The user is asking about what is on their screen right now. Call '
      'capture_screen exactly once, then answer based on the screenshot.';

  @override
  List<ToolSpec> get tools => [
        ToolSpec(
          name: 'capture_screen',
          description: 'Take a screenshot of the current screen. args: {}',
          run: (_) async {
            if (!await WranglNative.isScreenReady()) {
              return ToolResult.text(
                'ERROR: screen access is off. Tell the user to enable '
                '"Screen access" in the Wrangl launcher.',
              );
            }
            final bytes = await WranglNative.captureScreen();
            if (bytes == null) {
              return ToolResult.text('ERROR: could not capture the screen.');
            }
            return ToolResult.image(bytes);
          },
        ),
      ];
}
