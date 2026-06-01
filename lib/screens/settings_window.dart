import 'package:flutter/material.dart';
import 'package:wrangl_native/wrangl_native.dart';
import '../features/wallpaper/wallpaper_service.dart';

class SettingsWindowContent extends StatefulWidget {
  const SettingsWindowContent({super.key});

  @override
  State<SettingsWindowContent> createState() => _SettingsWindowContentState();
}

class _SettingsWindowContentState extends State<SettingsWindowContent> {
  final WallpaperService _wallpaper = WallpaperService();

  @override
  void initState() {
    super.initState();
    _wallpaper.load();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF1A1A1A),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                const Icon(Icons.settings_outlined,
                    color: Color(0xFFF0EFEB), size: 16),
                const SizedBox(width: 6),
                const Text(
                  'Settings',
                  style: TextStyle(
                    color: Color(0xFFF0EFEB),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const Divider(color: Color(0xFF444444), height: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(8),
              children: [
                _section('Appearance'),
                _settingTile(
                  Icons.wallpaper_outlined,
                  'Wallpaper',
                  'Change canvas background',
                  () => _wallpaper.pickAndSet().then((_) {
                    if (mounted) setState(() {});
                  }),
                ),
                _settingTile(
                  Icons.wallpaper_outlined,
                  'Reset Wallpaper',
                  'Remove custom wallpaper',
                  () => _wallpaper.reset().then((_) {
                    if (mounted) setState(() {});
                  }),
                ),
                const SizedBox(height: 12),
                _section('System'),
                _settingTile(
                  Icons.widgets_outlined,
                  'Widgets',
                  'Manage home screen widgets',
                  _showWidgetSettings,
                ),
                _settingTile(
                  Icons.wifi_outlined,
                  'Wi-Fi',
                  'Open Wi-Fi settings',
                  () => WranglNative.openSetting('wifi'),
                ),
                _settingTile(
                  Icons.bluetooth_outlined,
                  'Bluetooth',
                  'Open Bluetooth settings',
                  () => WranglNative.openSetting('bluetooth'),
                ),
                _settingTile(
                  Icons.notifications_outlined,
                  'Notifications',
                  'Open notification settings',
                  () => WranglNative.openSetting('notification'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(String label) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFFFF5C35),
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _settingTile(
      IconData icon, String label, String subtitle, VoidCallback onTap) {
    return ListTile(
      dense: true,
      leading: Icon(icon, color: const Color(0xFFF0EFEB), size: 20),
      title: Text(
        label,
        style: const TextStyle(color: Color(0xFFF0EFEB), fontSize: 13),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(color: Color(0xFF666666), fontSize: 11),
      ),
      onTap: onTap,
    );
  }

  void _showWidgetSettings() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        title: const Text(
          'App Widgets',
          style: TextStyle(color: Color(0xFFF0EFEB)),
        ),
        content: const Text(
          'Widget management will be available here.',
          style: TextStyle(color: Color(0xFFBBBBBB)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close',
                style: TextStyle(color: Color(0xFFFF5C35))),
          ),
        ],
      ),
    );
  }
}
