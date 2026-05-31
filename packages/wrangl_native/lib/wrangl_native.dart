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

  /// All launchable apps. Each map has `packageName` (String), `label` (String),
  /// and `icon` (Uint8List? — PNG bytes, may be null).
  static Future<List<Map<String, dynamic>>> getInstalledApps() async {
    final raw = await _ch.invokeListMethod<Map>('getInstalledApps') ?? [];
    return raw.map((m) => Map<String, dynamic>.from(m)).toList();
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

  // ── File search (MediaStore) ─────────────────────────────────────────────────

  /// Search device files by name and/or MIME type category.
  /// [mimeType] accepts: "image", "video", "audio", "document", or a raw MIME prefix.
  /// Returns up to 50 matches sorted by most recently modified.
  static Future<List<Map<String, dynamic>>> scanFiles({
    String? query,
    String? mimeType,
  }) async {
    final args = <String, dynamic>{};
    if (query != null) args['query'] = query;
    if (mimeType != null) args['mimeType'] = mimeType;
    final raw = await _ch.invokeListMethod<Map>('scanFiles', args) ?? [];
    return raw.map((m) => Map<String, dynamic>.from(m)).toList();
  }

  // ── Settings deep-links ─────────────────────────────────────────────────────

  /// Open a system settings panel by key (e.g. "wifi", "bluetooth", "display").
  /// Returns true if the intent was launched successfully.
  static Future<bool> openSetting(String key) async {
    return await _ch.invokeMethod<bool>(
          'openSetting',
          {'key': key},
        ) ??
        false;
  }

  /// Opens the system "Default home app" settings page so the user can set
  /// Wrangl as the default launcher (required for widget hosting on API 35+).
  static Future<bool> openHomeSettings() async {
    return await _ch.invokeMethod<bool>('openHomeSettings') ?? false;
  }

  // ── SMS reading (requires READ_SMS permission) ─────────────────────────────

  /// Read recent SMS messages from the inbox.
  /// [limit] max messages to return (default 20, max 100).
  /// Throws on permission denied or read failure.
  static Future<List<Map<String, dynamic>>> readSms({int limit = 20}) async {
    final raw = await _ch.invokeListMethod<Map>(
          'readSms',
          {'limit': limit},
        ) ??
        [];
    return raw.map((m) => Map<String, dynamic>.from(m)).toList();
  }

  /// Open the system uninstall screen for the given package.
  static Future<bool> uninstallApp(String packageName) async {
    return await _ch.invokeMethod<bool>(
          'uninstallApp',
          {'packageName': packageName},
        ) ??
        false;
  }

  /// Opens the system file/image picker from the main activity context.
  /// Returns a map with `name` (String) and `bytes` (Uint8List) of the selected file,
  /// or null if the selection was cancelled.
  static Future<Map<String, dynamic>?> pickFile() async {
    try {
      final raw = await _ch.invokeMapMethod<String, dynamic>('pickFile');
      return raw;
    } catch (e) {
      return null;
    }
  }
}
