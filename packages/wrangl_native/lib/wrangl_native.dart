import 'package:flutter/services.dart';

/// Native bridge for Wrangl. Because this is a real plugin package, its
/// MethodChannel auto-registers on **every** Flutter engine — including the
/// overlay isolate — so the floating bubble can call these directly.
class WranglNative {
  WranglNative._();

  static const MethodChannel _ch = MethodChannel('wrangl/native');

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

  // ── Screen capture (MediaProjection) ─────────────────────────────────────────

  /// Ask the user for screen-capture consent and start the capture service.
  /// Must be called from the main app (it needs an Activity). Returns true once
  /// consent is granted and the capture service is running.
  static Future<bool> requestScreenConsent() async {
    return await _ch.invokeMethod<bool>('requestScreenConsent') ?? false;
  }

  /// Whether the capture service currently holds a live MediaProjection.
  static Future<bool> isScreenReady() async {
    return await _ch.invokeMethod<bool>('isScreenReady') ?? false;
  }

  /// Grab a single downscaled JPEG frame of the current screen, or null if
  /// capture isn't available. Safe to call from the overlay isolate.
  static Future<Uint8List?> captureScreen() async {
    return await _ch.invokeMethod<Uint8List>('captureScreen');
  }

  /// Tear down the capture service and release the projection.
  static Future<void> stopScreen() async {
    await _ch.invokeMethod<void>('stopScreen');
  }
}
