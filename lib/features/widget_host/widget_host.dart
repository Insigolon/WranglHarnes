import 'package:flutter/services.dart';

class WidgetHostException implements Exception {
  final String code;
  final String message;
  const WidgetHostException(this.code, this.message);

  @override
  String toString() => 'WidgetHostException($code): $message';
}

class WidgetHostProvider {
  final String providerPackage;
  final String providerClass;
  final String providerLabel;
  final int minWidthDp;
  final int minHeightDp;

  const WidgetHostProvider({
    required this.providerPackage,
    required this.providerClass,
    required this.providerLabel,
    required this.minWidthDp,
    required this.minHeightDp,
  });

  factory WidgetHostProvider.fromMap(Map<String, dynamic> m) => WidgetHostProvider(
        providerPackage: m['providerPackage'] as String,
        providerClass: m['providerClass'] as String,
        providerLabel: m['providerLabel'] as String,
        minWidthDp: m['minWidthDp'] as int,
        minHeightDp: m['minHeightDp'] as int,
      );
}

class WidgetHostEntry {
  final int appWidgetId;
  final String providerPackage;
  final String providerLabel;
  final int minWidthDp;
  final int minHeightDp;

  const WidgetHostEntry({
    required this.appWidgetId,
    required this.providerPackage,
    required this.providerLabel,
    required this.minWidthDp,
    required this.minHeightDp,
  });

  factory WidgetHostEntry.fromMap(Map<String, dynamic> m) => WidgetHostEntry(
        appWidgetId: m['appWidgetId'] as int,
        providerPackage: m['providerPackage'] as String,
        providerLabel: m['providerLabel'] as String,
        minWidthDp: m['minWidthDp'] as int,
        minHeightDp: m['minHeightDp'] as int,
      );

  Map<String, dynamic> toMap() => {
        'appWidgetId': appWidgetId,
        'providerPackage': providerPackage,
        'providerLabel': providerLabel,
        'minWidthDp': minWidthDp,
        'minHeightDp': minHeightDp,
      };
}

class WidgetHost {
  static const _ch = MethodChannel('wrangl/native');

  static Future<List<WidgetHostProvider>> listProviders() async {
    final raw = await _ch.invokeListMethod<Map>('listWidgetProviders') ?? [];
    return raw
        .map((m) => WidgetHostProvider.fromMap(Map<String, dynamic>.from(m)))
        .toList();
  }

  static Future<WidgetHostEntry?> bindWidget(
      String providerPackage, String providerClass) async {
    try {
      final raw = await _ch.invokeMethod<Map>('bindWidget', {
        'providerPackage': providerPackage,
        'providerClass': providerClass,
      });
      if (raw == null) return null;
      return WidgetHostEntry.fromMap(Map<String, dynamic>.from(raw));
    } on PlatformException catch (e) {
      throw WidgetHostException(e.code, e.message ?? 'Unknown error');
    }
  }

  static Future<List<WidgetHostEntry>> refreshWidgets() async {
    final raw = await _ch.invokeListMethod<Map>('refreshWidgets') ?? [];
    return raw
        .map((m) => WidgetHostEntry.fromMap(Map<String, dynamic>.from(m)))
        .toList();
  }

  static Future<bool> removeWidget(int appWidgetId) async {
    final result =
        await _ch.invokeMethod<bool>('removeWidget', {'appWidgetId': appWidgetId});
    return result ?? false;
  }

  static Future<void> reorderWidgets(List<int> widgetIds) async {
    await _ch.invokeMethod('setWidgetOrder', {'widgetIds': widgetIds});
  }
}
