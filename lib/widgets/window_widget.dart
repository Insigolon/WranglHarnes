import 'package:flutter/material.dart';
import '../models/window_data.dart';
import '../services/window_manager.dart';
import 'resize_handle.dart';
import 'window_content.dart';

class WindowWidget extends StatefulWidget {
  final WindowData data;
  final double scale;
  final WindowManager manager;

  const WindowWidget({
    super.key,
    required this.data,
    required this.scale,
    required this.manager,
  });

  @override
  State<WindowWidget> createState() => _WindowWidgetState();
}

class _WindowWidgetState extends State<WindowWidget> {
  bool get _miniMode => widget.scale < 0.4;

  @override
  Widget build(BuildContext context) {
    return _miniMode ? _buildMini() : _buildFull();
  }

  Widget _buildMini() {
    return Container(
      width: 80,
      height: 90,
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A).withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF444444), width: 1),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            widget.data.icon ?? Icons.window,
            color: Colors.grey[400],
            size: 28,
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              widget.data.label ?? 'Window',
              style: const TextStyle(color: Colors.grey, fontSize: 10),
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFull() {
    return Container(
      width: widget.data.size.width,
      height: widget.data.size.height,
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: const Color(0xFF555555),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          _buildTitleBar(),
          Expanded(child: WindowContent(data: widget.data)),
          if (widget.data.type == WindowContentType.flutterScreen)
            Align(
              alignment: Alignment.bottomRight,
              child: ResizeHandle(
                onResize: (delta) {
                  widget.manager.updateSize(
                    widget.data.id,
                    Size(
                      widget.data.size.width + delta.dx,
                      widget.data.size.height + delta.dy,
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTitleBar() {
    return GestureDetector(
      onPanStart: (_) {
        widget.manager.bringToFront(widget.data);
      },
      onPanUpdate: (details) {
        final newPos = widget.data.position + details.delta;
        widget.manager.updateSnapGuides(widget.data.id);
        final snapped = widget.manager.snapPosition(
          widget.data.id,
          newPos,
        );
        widget.manager.setPosition(widget.data.id, snapped);
      },
      onPanEnd: (_) {
        widget.manager.clearSnapGuides();
      },
      child: Container(
        height: 36,
        decoration: const BoxDecoration(
          color: Color(0xFF2A2A2A),
          borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
        ),
        child: Row(
          children: [
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => widget.manager.removeWindow(widget.data.id),
              child: Container(
                width: 12,
                height: 12,
                decoration: const BoxDecoration(
                  color: Color(0xFFFF5C35),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Container(
              width: 12,
              height: 12,
              decoration: const BoxDecoration(
                color: Color(0xFF888888),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                widget.data.label ?? 'Window',
                style: const TextStyle(
                  color: Color(0xFFF0EFEB),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
