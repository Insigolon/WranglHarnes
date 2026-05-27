import 'dart:async';
import 'package:flutter/services.dart';

/// Native bridge for Wrangl. Because this is a real plugin package, its
/// MethodChannel auto-registers on **every** Flutter engine — including the
/// overlay isolate — so the floating bubble can call these directly.
class WranglNative {
  WranglNative._();

  static const MethodChannel _ch = MethodChannel('wrangl/native');
  static const EventChannel _assistCh = EventChannel('wrangl/assist_events');

  // ── App launching ──────────────────────────────────────────────────────────

  /// All launchable apps as `{packageName, label}` maps, sorted by label.
  static Future<List<Map<String, String>>> getInstalledApps() async {
    final raw = await _ch.invokeListMethod<Map>('getInstalledApps') ?? [];
    return raw
        .map((m) => {
              'packageName': m['packageName'] as String,
              'label': m['label'] as String,
            })
        .toList();
  }

  /// Launch an app by package name. Returns false if it has no launch intent.
  static Future<bool> launchApp(String packageName) async {
    return await _ch.invokeMethod<bool>(
          'launchApp',
          {'packageName': packageName},
        ) ??
        false;
  }

  // ── Screen capture (MediaProjection) ──────────────────────────────────────

  /// Capture the current screen contents via MediaProjection.
  /// Returns JPEG bytes or throws if permission was denied or capture failed.
  /// The first call triggers a system consent dialog; subsequent calls are
  /// automatic.
  static Future<Uint8List> captureScreen() async {
    final raw = await _ch.invokeMethod<Uint8List>('captureScreen');
    if (raw == null) throw Exception('Screen capture returned no data');
    return raw;
  }

  // ── Assist event stream ──────────────────────────────────────────────────────

  /// Listen for assist events pushed from native (e.g. double-tap back).
  /// Payload: `{"image": Uint8List?, "hint": String?}`.
  static Stream<Map<String, dynamic>> get assistStream =>
      _assistCh.receiveBroadcastStream().map(
            (e) => Map<String, dynamic>.from(e as Map),
          );
}
