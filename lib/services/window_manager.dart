import 'dart:collection';
import 'package:flutter/material.dart';
import '../models/window_data.dart';

class SnapGuide {
  final double offset;
  final bool isHorizontal;
  final Rect source;
  final Rect target;

  SnapGuide({
    required this.offset,
    required this.isHorizontal,
    required this.source,
    required this.target,
  });
}

class WindowManager extends ChangeNotifier {
  final List<WindowData> _windows = [];
  int _highestZ = 0;
  List<SnapGuide> _snapGuides = [];
  final double snapThreshold = 20.0;

  UnmodifiableListView<WindowData> get windows =>
      UnmodifiableListView(_windows);

  List<SnapGuide> get snapGuides => _snapGuides;

  void addWindow(WindowData window) {
    _highestZ++;
    window.zIndex = _highestZ;
    _windows.add(window);
    _windows.sort((a, b) => a.zIndex.compareTo(b.zIndex));
    notifyListeners();
  }

  void removeWindow(String id) {
    _windows.removeWhere((w) => w.id == id);
    notifyListeners();
  }

  void bringToFront(WindowData window) {
    _highestZ++;
    window.zIndex = _highestZ;
    _windows.sort((a, b) => a.zIndex.compareTo(b.zIndex));
    notifyListeners();
  }

  void updatePosition(String id, Offset delta) {
    final idx = _windows.indexWhere((w) => w.id == id);
    if (idx == -1) return;
    _windows[idx].position += delta;
    notifyListeners();
  }

  void setPosition(String id, Offset position) {
    final idx = _windows.indexWhere((w) => w.id == id);
    if (idx == -1) return;
    _windows[idx].position = position;
    notifyListeners();
  }

  void updateSize(String id, Size size) {
    final idx = _windows.indexWhere((w) => w.id == id);
    if (idx == -1) return;
    _windows[idx].size = Size(
      size.width.clamp(150, 5000),
      size.height.clamp(100, 5000),
    );
    notifyListeners();
  }

  void updateSnapGuides(String movingId) {
    _snapGuides = [];
    final movingIdx = _windows.indexWhere((w) => w.id == movingId);
    if (movingIdx == -1) return;
    final moving = _windows[movingIdx];
    final movingRect = Rect.fromLTWH(
      moving.position.dx,
      moving.position.dy,
      moving.size.width,
      moving.size.height,
    );

    for (final other in _windows) {
      if (other.id == movingId) continue;
      final otherRect = Rect.fromLTWH(
        other.position.dx,
        other.position.dy,
        other.size.width,
        other.size.height,
      );

      // Vertical alignment: left edges, right edges, center X
      _checkAlignment(
        movingRect.left,
        otherRect.left,
        true,
        movingRect,
        otherRect,
      );
      _checkAlignment(
        movingRect.right,
        otherRect.right,
        true,
        movingRect,
        otherRect,
      );
      _checkAlignment(
        movingRect.center.dx,
        otherRect.center.dx,
        true,
        movingRect,
        otherRect,
      );

      // Horizontal alignment: top edges, bottom edges, center Y
      _checkAlignment(
        movingRect.top,
        otherRect.top,
        false,
        movingRect,
        otherRect,
      );
      _checkAlignment(
        movingRect.bottom,
        otherRect.bottom,
        false,
        movingRect,
        otherRect,
      );
      _checkAlignment(
        movingRect.center.dy,
        otherRect.center.dy,
        false,
        movingRect,
        otherRect,
      );
    }
  }

  void _checkAlignment(
    double movingCoord,
    double otherCoord,
    bool isHorizontal,
    Rect movingRect,
    Rect otherRect,
  ) {
    if ((movingCoord - otherCoord).abs() < snapThreshold) {
      _snapGuides.add(SnapGuide(
        offset: otherCoord,
        isHorizontal: isHorizontal,
        source: movingRect,
        target: otherRect,
      ));
    }
  }

  Offset snapPosition(String id, Offset desiredPosition) {
    final movingIdx = _windows.indexWhere((w) => w.id == id);
    if (movingIdx == -1) return desiredPosition;
    final moving = _windows[movingIdx];
    final movingRect = Rect.fromLTWH(
      desiredPosition.dx,
      desiredPosition.dy,
      moving.size.width,
      moving.size.height,
    );
    var snappedX = desiredPosition.dx;
    var snappedY = desiredPosition.dy;

    for (final other in _windows) {
      if (other.id == id) continue;
      final otherRect = Rect.fromLTWH(
        other.position.dx,
        other.position.dy,
        other.size.width,
        other.size.height,
      );

      if ((movingRect.left - otherRect.left).abs() < snapThreshold) {
        snappedX = otherRect.left;
      }
      if ((movingRect.right - otherRect.right).abs() < snapThreshold) {
        snappedX = otherRect.right - moving.size.width;
      }
      if ((movingRect.center.dx - otherRect.center.dx).abs() <
          snapThreshold) {
        snappedX = otherRect.center.dx - moving.size.width / 2;
      }

      if ((movingRect.top - otherRect.top).abs() < snapThreshold) {
        snappedY = otherRect.top;
      }
      if ((movingRect.bottom - otherRect.bottom).abs() < snapThreshold) {
        snappedY = otherRect.bottom - moving.size.height;
      }
      if ((movingRect.center.dy - otherRect.center.dy).abs() <
          snapThreshold) {
        snappedY = otherRect.center.dy - moving.size.height / 2;
      }
    }
    return Offset(snappedX, snappedY);
  }

  void clearSnapGuides() {
    _snapGuides = [];
    notifyListeners();
  }

  List<WindowData> fromJsonList(List<dynamic> jsonList) {
    return jsonList
        .map((j) => WindowData.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  List<Map<String, dynamic>> toJsonList() =>
      _windows.map((w) => w.toJson()).toList();

  void loadFromList(List<WindowData> windows) {
    _windows.clear();
    _windows.addAll(windows);
    _highestZ = windows.fold(0, (max, w) => w.zIndex > max ? w.zIndex : max);
    _windows.sort((a, b) => a.zIndex.compareTo(b.zIndex));
    notifyListeners();
  }
}
