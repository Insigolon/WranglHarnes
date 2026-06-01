import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

enum WindowContentType { androidApp, flutterScreen, appWidget }

class WindowData {
  final String id;
  Offset position;
  Size size;
  int zIndex;
  WindowContentType type;
  String? packageName;
  String? screenId;
  Widget? flutterChild;
  int? appWidgetId;
  String? label;
  IconData? icon;

  WindowData({
    String? id,
    this.position = Offset.zero,
    this.size = const Size(350, 500),
    this.zIndex = 0,
    this.type = WindowContentType.flutterScreen,
    this.packageName,
    this.screenId,
    this.flutterChild,
    this.appWidgetId,
    this.label,
    this.icon,
  }) : id = id ?? const Uuid().v4();

  Map<String, dynamic> toJson() => {
        'id': id,
        'x': position.dx,
        'y': position.dy,
        'width': size.width,
        'height': size.height,
        'zIndex': zIndex,
        'type': type.index,
        'packageName': packageName,
        'screenId': screenId,
        'appWidgetId': appWidgetId,
        'label': label,
        if (icon != null) 'iconCodePoint': icon!.codePoint,
        if (icon != null) 'iconFontFamily': icon!.fontFamily,
      };

  factory WindowData.fromJson(Map<String, dynamic> json) => WindowData(
        id: json['id'] as String? ?? const Uuid().v4(),
        position: Offset(
          (json['x'] as num).toDouble(),
          (json['y'] as num).toDouble(),
        ),
        size: Size(
          (json['width'] as num).toDouble(),
          (json['height'] as num).toDouble(),
        ),
        zIndex: json['zIndex'] as int? ?? 0,
        type: WindowContentType.values[json['type'] as int? ?? 1],
        packageName: json['packageName'] as String?,
        screenId: json['screenId'] as String?,
        appWidgetId: json['appWidgetId'] as int?,
        label: json['label'] as String?,
        icon: json['iconCodePoint'] != null
            ? IconData(
                json['iconCodePoint'] as int,
                fontFamily: json['iconFontFamily'] as String?,
              )
            : null,
      );
}
