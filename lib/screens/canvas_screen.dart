import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:wrangl_native/wrangl_native.dart';
import '../features/wallpaper/wallpaper_service.dart';
import '../features/widget_host/widget_host_service.dart';
import '../models/window_data.dart';
import '../services/window_manager.dart';
import '../services/workspace_storage.dart';
import '../widgets/infinite_canvas.dart';
import '../widgets/dock.dart';
import 'notes_window.dart';
import 'chat_window.dart';
import 'settings_window.dart';
import 'agent_window.dart';

class CanvasScreen extends StatefulWidget {
  const CanvasScreen({super.key});

  @override
  State<CanvasScreen> createState() => CanvasScreenState();
}

class CanvasScreenState extends State<CanvasScreen> {
  final WindowManager windowManager = WindowManager();
  final WorkspaceStorage workspaceStorage = WorkspaceStorage();
  final WallpaperService wallpaper = WallpaperService();
  final WidgetHostService widgetHost = WidgetHostService();

  List<Map<String, dynamic>> _apps = [];

  Timer? _saveDebounce;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(_onWindowsChanged);
    _initCanvas();
  }

  void _onWindowsChanged() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(seconds: 1), () {
      saveWorkspace();
    });
  }

  Future<void> _initCanvas() async {
    await workspaceStorage.load();
    windowManager.loadFromList(
      workspaceStorage.activeWorkspace.windows,
    );
    wallpaper.load();
    widgetHost.load();
    _loadApps();
  }

  Future<void> _loadApps() async {
    try {
      final apps = await WranglNative.getInstalledApps();
      if (mounted) setState(() => _apps = apps);
    } catch (_) {}
  }

  int _nextStackOffset = 0;

  Future<void> spawnAndroidAppWindow(Map<String, dynamic> app) async {
    final windowId = const Uuid().v4();
    final packageName = app['packageName'] as String? ?? '';
    int displayId = -1;
    try {
      displayId = await WranglNative.createAppWindow(
        windowId: windowId,
        packageName: packageName,
        width: 400,
        height: 600,
      );
    } catch (_) {}

    final window = WindowData(
      id: windowId,
      position: Offset(
        200 + _nextStackOffset * 40.0,
        200 + _nextStackOffset * 40.0,
      ),
      size: const Size(400, 600),
      type: WindowContentType.androidApp,
      packageName: packageName,
      screenId: displayId > 0 ? windowId : null,
      label: app['label'] as String? ?? 'App',
      icon: Icons.phone_android,
    );
    windowManager.addWindow(window);
    _nextStackOffset++;
  }

  void spawnFlutterWindow({
    required String label,
    required IconData icon,
    required Widget child,
    Size? size,
  }) {
    final window = WindowData(
      position: Offset(
        200 + _nextStackOffset * 30.0,
        200 + _nextStackOffset * 30.0,
      ),
      size: size ?? const Size(350, 500),
      type: WindowContentType.flutterScreen,
      flutterChild: child,
      label: label,
      icon: icon,
    );
    windowManager.addWindow(window);
    _nextStackOffset++;
  }

  Future<void> saveWorkspace() async {
    final snapshot = windowManager.windows
        .map((w) => WindowData.fromJson(w.toJson()))
        .toList();
    workspaceStorage.activeWorkspace.windows = snapshot;
    await workspaceStorage.save();
  }

  Future<void> switchWorkspace(int index) async {
    workspaceStorage.activeWorkspace.windows = windowManager.windows.toList();
    await workspaceStorage.switchWorkspace(index);
    windowManager.loadFromList(
      workspaceStorage.activeWorkspace.windows,
    );
  }

  void _showAppDrawer() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _buildAppDrawer(),
    );
  }

  Future<void> _launchAppExternal(Map<String, dynamic> app) async {
    final pkg = app['packageName'] as String?;
    if (pkg != null) {
      await WranglNative.launchApp(pkg);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      body: Stack(
        children: [
          if (wallpaper.value != null)
            Positioned.fill(
              child: Image.memory(
                wallpaper.value!,
                fit: BoxFit.cover,
                color: Colors.black.withValues(alpha: 0.3),
                colorBlendMode: BlendMode.darken,
              ),
            ),
          InfiniteCanvas(manager: windowManager),
          Dock(
            manager: windowManager,
            items: _dockItems(),
            onOpenAppDrawer: _showAppDrawer,
            showWorkspaceSwitcher: true,
            workspaceNames:
                workspaceStorage.workspaces.map((w) => w.name).toList(),
            activeWorkspaceIndex: workspaceStorage.activeIndex,
            onWorkspaceChanged: (i) => switchWorkspace(i),
          ),
        ],
      ),
    );
  }

  List<DockItem> _dockItems() {
    return [
      DockItem(
        label: 'Chat',
        icon: Icons.chat_bubble_outline,
        content: const ChatWindowContent(),
      ),
      DockItem(
        label: 'Notes',
        icon: Icons.note_outlined,
        content: const NotesWindowContent(),
      ),
      DockItem(
        label: 'Agent',
        icon: Icons.psychology_outlined,
        content: const AgentWindowContent(),
      ),
      DockItem(
        label: 'Settings',
        icon: Icons.settings_outlined,
        content: const SettingsWindowContent(),
      ),
    ];
  }

  Widget _buildAppDrawer() {
    return Container(
      height: MediaQuery.of(context).size.height * 0.6,
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFF555555),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          const Row(
            children: [
              Icon(Icons.apps, color: Color(0xFFF0EFEB), size: 20),
              SizedBox(width: 8),
              Text(
                'Installed Apps',
                style: TextStyle(
                  color: Color(0xFFF0EFEB),
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(color: Color(0xFF444444)),
          Expanded(
            child: _apps.isEmpty
                ? const Center(
                    child: Text(
                      'No apps loaded',
                      style: TextStyle(color: Color(0xFF666666)),
                    ),
                  )
                : GridView.builder(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 4,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                    ),
                    itemCount: _apps.length,
                    itemBuilder: (_, i) {
                      final app = _apps[i];
                      return GestureDetector(
                        onTap: () {
                          Navigator.pop(context);
                          spawnAndroidAppWindow(app);
                        },
                        onLongPress: () {
                          Navigator.pop(context);
                          _launchAppExternal(app);
                        },
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                color: const Color(0xFF2A2A2A),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: _buildAppIcon(app['icon'] as Uint8List?),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              app['label'] as String? ?? '?',
                              style: const TextStyle(
                                color: Color(0xFFF0EFEB),
                                fontSize: 11,
                              ),
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppIcon(Uint8List? bytes) {
    if (bytes == null || bytes.isEmpty) {
      return const Icon(Icons.android, color: Color(0xFF888888), size: 28);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Image.memory(bytes, width: 56, height: 56, fit: BoxFit.cover),
    );
  }

  @override
  void dispose() {
    windowManager.removeListener(_onWindowsChanged);
    _saveDebounce?.cancel();
    saveWorkspace();
    super.dispose();
  }
}
