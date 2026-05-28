import 'package:wrangl_native/wrangl_native.dart';

import '../../agent/harness/model.dart';
import '../../core/agent/tool_registry.dart';

const Map<String, String> kSettingsDescriptions = {
  'wifi':
      'Change Wi-Fi connections, turn Wi-Fi on/off, connect to networks',
  'bluetooth':
      'Manage Bluetooth connections, pair devices, turn Bluetooth on/off',
  'mobile_data':
      'Configure mobile data, roaming, APN settings',
  'airplane_mode':
      'Turn airplane mode on/off, disable all wireless connections',
  'display':
      'Adjust screen brightness, wallpaper, sleep timeout, font size',
  'sound':
      'Change ringtone, media volume, notification sounds, vibration',
  'notification':
      'Manage app notification permissions, alert styles, do not disturb',
  'battery':
      'View battery usage, enable battery saver, optimize power',
  'storage':
      'View and manage internal storage, free up space',
  'location':
      'Change location mode, manage app location permissions',
  'security':
      'Manage screen lock, fingerprint, face unlock, device admin apps',
  'apps':
      'View all installed apps, manage app permissions, defaults',
  'language_input':
      'Change system language, keyboard settings, spell check',
  'accessibility':
      'Accessibility features, screen reader, magnification, captions',
  'about_phone':
      'View device info, status, software updates, legal information',
  'date_time':
      'Set date, time, time zone, date format, use network time',
  'developer_options':
      'Developer options, USB debugging, GPU rendering, animation scale',
  'hotspot':
      'Configure portable Wi-Fi hotspot, USB tethering, Bluetooth tethering',
  'vpn':
      'Manage VPN connections, add or configure VPN profiles',
  'wallpaper':
      'Change home screen and lock screen wallpaper',
};

class SettingsSearchService {
  final ModelComplete? _complete;

  SettingsSearchService([this._complete]);

  Future<bool> openSetting(String key) async {
    return WranglNative.openSetting(key);
  }

  Future<String> findAndLaunch(String query) async {
    final model = _complete ?? kModelComplete;
    if (model == null) return 'ERROR: model not loaded';

    final buffer =
        StringBuffer('I have these settings available on this Android device:\n');
    for (final entry in kSettingsDescriptions.entries) {
      buffer.writeln('- ${entry.key}: ${entry.value}');
    }
    buffer.writeln();
    buffer.writeln('The user wants: "$query"');
    buffer.writeln();
    buffer.writeln(
        'Which setting key matches best? Reply with ONLY the key name (e.g., "wifi").');

    final key = await model(
      system: '',
      history: [
        {'role': 'user', 'content': buffer.toString()},
      ],
      maxTokens: 32,
    );

    final matchedKey = key.trim().toLowerCase();
    if (!kSettingsDescriptions.containsKey(matchedKey)) {
      final ok = await WranglNative.openSetting('settings');
      return ok ? 'Opened main Settings.' : 'Failed to open Settings.';
    }

    final ok = await WranglNative.openSetting(matchedKey);
    return ok
        ? 'Opened ${matchedKey.replaceAll('_', ' ')} settings.'
        : 'Failed to open $matchedKey settings.';
  }
}
