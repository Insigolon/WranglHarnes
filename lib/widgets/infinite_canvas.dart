import 'package:flutter/material.dart';
import '../models/window_data.dart';
import '../services/window_manager.dart';
import 'window_widget.dart';

class InfiniteCanvas extends StatefulWidget {
  final WindowManager manager;

  const InfiniteCanvas({super.key, required this.manager});

  @override
  State<InfiniteCanvas> createState() => _InfiniteCanvasState();
}

class _InfiniteCanvasState extends State<InfiniteCanvas> {
  double _scale = 1.0;
  final TransformationController _transformCtrl = TransformationController();

  @override
  void initState() {
    super.initState();
    _transformCtrl.addListener(() {
      final scale = _transformCtrl.value.getMaxScaleOnAxis();
      if ((scale - _scale).abs() > 0.01) {
        setState(() => _scale = scale);
      }
    });
    widget.manager.addListener(_onWindowsChanged);
  }

  @override
  void dispose() {
    widget.manager.removeListener(_onWindowsChanged);
    _transformCtrl.dispose();
    super.dispose();
  }

  void _onWindowsChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: InteractiveViewer(
        transformationController: _transformCtrl,
        constrained: false,
        boundaryMargin: EdgeInsets.all(double.infinity),
        minScale: 0.2,
        maxScale: 5.0,
        child: SizedBox(
          width: 10000,
          height: 10000,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              ...widget.manager.windows.map(
                (w) => _buildWindow(w),
              ),
              ...widget.manager.snapGuides.map(
                (g) => _buildGuide(g),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWindow(WindowData data) {
    return Positioned(
      left: data.position.dx,
      top: data.position.dy,
      child: WindowWidget(
        data: data,
        scale: _scale,
        manager: widget.manager,
      ),
    );
  }

  Widget _buildGuide(SnapGuide guide) {
    if (guide.isHorizontal) {
      return Positioned(
        left: 0,
        top: guide.offset,
        right: 0,
        child: IgnorePointer(
          child: Container(
            height: 1,
            color: Colors.cyan.withValues(alpha: 0.8),
          ),
        ),
      );
    }
    return Positioned(
      left: guide.offset,
      top: 0,
      bottom: 0,
      child: IgnorePointer(
        child: Container(
          width: 1,
          color: Colors.cyan.withValues(alpha: 0.8),
        ),
      ),
    );
  }
}
