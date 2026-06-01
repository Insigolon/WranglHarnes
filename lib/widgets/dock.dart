import 'package:flutter/material.dart';
import '../models/window_data.dart';
import '../services/window_manager.dart';

class DockItem {
  final String label;
  final IconData icon;
  final WindowContentType contentType;
  final Widget? content;
  final String? packageName;

  const DockItem({
    required this.label,
    required this.icon,
    this.contentType = WindowContentType.flutterScreen,
    this.content,
    this.packageName,
  });
}

class Dock extends StatelessWidget {
  final WindowManager manager;
  final List<DockItem> items;
  final VoidCallback? onOpenAppDrawer;
  final bool showWorkspaceSwitcher;
  final List<String> workspaceNames;
  final int activeWorkspaceIndex;
  final ValueChanged<int>? onWorkspaceChanged;

  const Dock({
    super.key,
    required this.manager,
    this.items = const [],
    this.onOpenAppDrawer,
    this.showWorkspaceSwitcher = false,
    this.workspaceNames = const [],
    this.activeWorkspaceIndex = 0,
    this.onWorkspaceChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 16,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E).withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF444444), width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showWorkspaceSwitcher) ...[
                _workspaceSelector(),
                const SizedBox(width: 8),
                _divider(),
                const SizedBox(width: 8),
              ],
              ...items.map((item) => _dockButton(item)),
              if (onOpenAppDrawer != null) ...[
                const SizedBox(width: 4),
                _divider(),
                const SizedBox(width: 4),
                _iconButton(Icons.apps, 'Apps', onOpenAppDrawer!),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _divider() {
    return Container(
      width: 1,
      height: 24,
      color: const Color(0xFF444444),
    );
  }

  Widget _dockButton(DockItem item) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: _iconButton(item.icon, item.label, () {
        final offset = (manager.windows.length % 20) * 30.0;
        final window = WindowData(
          position: Offset(200 + offset, 200 + offset),
          size: const Size(350, 500),
          type: item.contentType,
          flutterChild: item.content,
          label: item.label,
          icon: item.icon,
        );
        manager.addWindow(window);
      }),
    );
  }

  Widget _iconButton(IconData icon, String tooltip, VoidCallback onTap) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: const Color(0xFF2A2A2A),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: const Color(0xFFF0EFEB), size: 22),
        ),
      ),
    );
  }

  Widget _workspaceSelector() {
    return PopupMenuButton<int>(
      onSelected: onWorkspaceChanged,
      offset: const Offset(0, -48),
      color: const Color(0xFF2A2A2A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      itemBuilder: (_) => List.generate(workspaceNames.length, (i) {
        return PopupMenuItem(
          value: i,
          child: Row(
            children: [
              if (i == activeWorkspaceIndex)
                const Icon(Icons.check, size: 16, color: Color(0xFFFF5C35)),
              if (i == activeWorkspaceIndex) const SizedBox(width: 8),
              Text(
                workspaceNames[i],
                style: const TextStyle(color: Color(0xFFF0EFEB)),
              ),
            ],
          ),
        );
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.grid_view_rounded,
                color: Color(0xFFF0EFEB), size: 18),
            const SizedBox(width: 6),
            Text(
              workspaceNames.isNotEmpty
                  ? workspaceNames[activeWorkspaceIndex]
                  : 'Home',
              style: const TextStyle(
                color: Color(0xFFF0EFEB),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.arrow_drop_down,
                color: Color(0xFF888888), size: 16),
          ],
        ),
      ),
    );
  }
}
