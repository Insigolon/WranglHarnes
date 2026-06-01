import 'package:flutter/material.dart';

class ResizeHandle extends StatelessWidget {
  final ValueChanged<Offset> onResize;

  const ResizeHandle({super.key, required this.onResize});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanUpdate: (details) => onResize(details.delta),
      child: Container(
        width: 24,
        height: 24,
        decoration: const BoxDecoration(
          color: Color(0xFF3A3A3A),
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(6),
            bottomRight: Radius.circular(8),
          ),
        ),
        child: const Icon(
          Icons.drag_handle,
          size: 14,
          color: Color(0xFF888888),
        ),
      ),
    );
  }
}
