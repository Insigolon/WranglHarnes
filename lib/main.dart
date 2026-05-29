import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:path_provider/path_provider.dart';
import 'package:wrangl_native/wrangl_native.dart';
import 'agent/model_config.dart';
import 'overlay/bubble_overlay.dart';
import 'screens/model_download_screen.dart';
import 'src/rust/api/simple.dart';
import 'src/rust/frb_generated.dart';
import 'features/wallpaper/wallpaper_service.dart';
import 'features/widget_host/widget_host_service.dart';
import 'features/widget_host/widget_host.dart';

/// Reliable overlay-permission bridge to [MainActivity]'s Kotlin channel.
/// Unlike `FlutterOverlayWindow.requestPermission()`, this suspends until the
/// user returns from Settings, then reports the real grant state.
class _OverlayPermission {
  _OverlayPermission._();
  static const _ch = MethodChannel('wrangl/overlay_permission');

  static Future<bool> isGranted() async =>
      (await _ch.invokeMethod<bool>('check')) ?? false;

  /// Opens the system "Display over other apps" page and returns `true` only
  /// after the user has granted the permission and returned to the app.
  static Future<bool> request() async =>
      (await _ch.invokeMethod<bool>('request')) ?? false;
}

class _AppLauncher {
  static Future<List<AppEntry>> getInstalledApps() async {
    final raw = await WranglNative.getInstalledApps();
    return raw
        .map(
          (m) => AppEntry(
            m['packageName'] as String,
            m['label'] as String,
            icon: m['icon'] as Uint8List?,
          ),
        )
        .toList();
  }

  static Future<void> openApp(String packageName) =>
      WranglNative.launchApp(packageName);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Bring up the Rust core (flutter_rust_bridge). This must run once per
  // isolate that calls into Rust. Validates the FFI toolchain end-to-end.
  await RustLib.init();
  debugPrint('[rust] ${greet(name: "Wrangl")}');

  // flutter_gemma 0.12.x requires explicit init per isolate before
  // installModel / getActiveModel. The overlay isolate does its own.
  await FlutterGemma.initialize();

  // The model file is loaded inside the overlay isolate, not here — the main
  // isolate only needs to know whether it has already been downloaded.
  final path = await ModelConfig.path();
  final file = File(path);
  final modelReady =
      await file.exists() && await file.length() > ModelConfig.minSize;

  runApp(MyApp(modelReady: modelReady));
}

/// Entry point for the overlay isolate spawned by flutter_overlay_window.
/// The native side launches the Dart function named exactly `overlayMain`.
@pragma('vm:entry-point')
void overlayMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The overlay isolate uses the Rust harness too, so init the bridge here.
  await RustLib.init();
  // Same plugin init as the main isolate — each Flutter isolate has its own
  // plugin state, and the overlay is the one that actually loads the model.
  await FlutterGemma.initialize();
  runApp(const WranglBubbleRoot());
}

class MyApp extends StatelessWidget {
  final bool modelReady;
  const MyApp({super.key, required this.modelReady});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      // If the model is already downloaded go straight to the launcher;
      // otherwise show the download screen exactly once.
      home: modelReady ? const RadialLauncher() : const ModelDownloadScreen(),
    );
  }
}

class AppEntry {
  final String packageName, label;
  final Uint8List? icon;
  const AppEntry(this.packageName, this.label, {this.icon});
}

class FolderEntry {
  final String name;
  final List<String> packageNames;
  final int iconIndex;
  const FolderEntry(this.name, this.packageNames, {this.iconIndex = 0});
}

const List<IconData> _folderIcons = [
  Icons.folder,
  Icons.folder_special,
  Icons.people,
  Icons.sports_esports,
  Icons.work,
  Icons.music_note,
  Icons.photo_library,
  Icons.videocam,
  Icons.settings,
  Icons.shopping_cart,
  Icons.school,
  Icons.favorite,
  Icons.home,
  Icons.person,
  Icons.public,
  Icons.flag,
];

// ─── Launcher constants ──────────────────────────────────────────────────────
const double _kArcStart = 160.0;
const double _kArcEnd = 290.0;
const double _kLauncherScale = 1.28;
const double _kLabelScale = 1.55;
const double _kHubR = 46.0 * _kLauncherScale;
const double _kInnerR = 72.0 * _kLauncherScale;
const double _kOuterR = 175.0 * _kLauncherScale;
const double _kCornerInset = 12.0 * _kLauncherScale;
const double _kButtonSweep = 18.0;
const double _kMenuStart = _kArcStart + _kButtonSweep;
const double _kMenuEnd = _kArcEnd - _kButtonSweep;
const int _kVisibleAppCount = 7;

const double _kDegToRad = math.pi / 180;
const double _kArcStartRad = _kArcStart * _kDegToRad;
const double _kArcEndRad = _kArcEnd * _kDegToRad;
const double _kMenuStartRad = _kMenuStart * _kDegToRad;
const double _kMenuEndRad = _kMenuEnd * _kDegToRad;
const double _kArcSpanRad = _kArcEndRad - _kArcStartRad;
const double _kMenuSpanRad = _kMenuEndRad - _kMenuStartRad;
const double _kInnerR2 = _kInnerR * _kInnerR;
const double _kOuterR2 = _kOuterR * _kOuterR;

final double _kArcRightReach = _kOuterR * math.cos(_kArcEndRad);

// ─── Radial launcher ────────────────────────────────────────────────────────

class RadialLauncher extends StatefulWidget {
  const RadialLauncher({super.key});

  @override
  State<RadialLauncher> createState() => _RadialLauncherState();
}

class _RadialLauncherState extends State<RadialLauncher>
    with TickerProviderStateMixin {
  // launcher state
  bool _open = false;
  int? _selSlot;
  int _offset = 0;
  List<AppEntry> _apps = const [];
  List<FolderEntry> _folders = const [];
  final Map<String, ui.Image> _appIconImages = {};
  final Stopwatch _pageStopwatch = Stopwatch()..start();

  List<Object> get _displayItems {
    final inFolders = _folders.expand((f) => f.packageNames).toSet();
    final unassigned = _apps
        .where((a) => !inFolders.contains(a.packageName))
        .toList();
    return [..._folders, ...unassigned];
  }

  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
  );
  late final Animation<double> _anim = CurvedAnimation(
    parent: _ctrl,
    curve: Curves.easeOutCubic,
  );

  final WallpaperService _wallpaper = WallpaperService();
  final WidgetHostService _widgetHost = WidgetHostService();

  bool _isEditing = false;
  late final AnimationController _editCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 500),
  );
  late final Animation<double> _editAnim = Tween<double>(
    begin: -0.03,
    end: 0.03,
  ).animate(CurvedAnimation(parent: _editCtrl, curve: Curves.easeInOut));

  @override
  void initState() {
    super.initState();
    _loadApps();
    _loadFolders();
    _wallpaper.load();
    _widgetHost.load();
    _widgetHost.addListener(_onWidgetsChanged);
  }

  Future<void> _loadApps() async {
    final entries = await _AppLauncher.getInstalledApps();
    if (!mounted) return;
    setState(() => _apps = entries);
    _loadAppIcons();
  }

  Future<void> _loadAppIcons() async {
    final images = <String, ui.Image>{};
    for (final app in _apps) {
      if (app.icon == null || app.icon!.isEmpty) continue;
      try {
        final codec = await ui.instantiateImageCodec(app.icon!);
        final frame = await codec.getNextFrame();
        images[app.packageName] = frame.image;
      } catch (_) {}
    }
    if (mounted) setState(() => _appIconImages..addAll(images));
  }

  Future<File> get _foldersFile async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/folders.json');
  }

  Future<void> _loadFolders() async {
    try {
      final file = await _foldersFile;
      if (await file.exists()) {
        final json = jsonDecode(await file.readAsString()) as List;
        if (mounted) {
          setState(() {
            _folders = json
                .map(
                  (e) => FolderEntry(
                    e['name'] as String,
                    (e['packageNames'] as List).cast<String>(),
                  ),
                )
                .toList();
          });
        }
      }
    } catch (e) {
      debugPrint('[folders] load failed: $e');
    }
  }

  Future<void> _saveFolders() async {
    final file = await _foldersFile;
    final json = jsonEncode(
      _folders
          .map((f) => {'name': f.name, 'packageNames': f.packageNames})
          .toList(),
    );
    await file.writeAsString(json);
  }

  // ── voice input → overlay with recording ───────────────

  Future<void> _startVoiceInput() async {
    final granted = await _OverlayPermission.isGranted();
    if (!granted) {
      final afterGrant = await _OverlayPermission.request();
      if (!afterGrant) {
        if (mounted) _showOverlayDeniedDialog();
        return;
      }
    }
    await _openOverlay(startVoice: true);
  }

  // ── overlay activation ──────────────────────────────────

  Future<void> _openOverlay({
    String? prefilledText,
    bool startVoice = false,
  }) async {
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    final screenW = (view.physicalSize.width / view.devicePixelRatio).round();
    try {
      await FlutterOverlayWindow.showOverlay(
        height: 200,
        width: screenW,
        alignment: OverlayAlignment.topCenter,
        flag: OverlayFlag.focusPointer,
        enableDrag: true,
        positionGravity: PositionGravity.none,
        startPosition: OverlayPosition(0, 50),
        overlayTitle: 'Wrangl',
        overlayContent: 'Chat with Gemma',
      );
      final data = <String, dynamic>{};
      if (prefilledText != null && prefilledText.isNotEmpty) {
        data['voiceText'] = prefilledText;
      }
      if (startVoice) {
        data['startVoice'] = true;
      }
      if (data.isNotEmpty) {
        await Future.delayed(const Duration(milliseconds: 600));
        await FlutterOverlayWindow.shareData(jsonEncode(data));
      }
    } catch (e) {
      debugPrint('[overlay] launch failed: $e');
    }
  }

  void _showOverlayDeniedDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text(
          'Overlay Permission Needed',
          style: TextStyle(color: Color(0xFFF0EFEB)),
        ),
        content: const Text(
          'Wrangl needs "Display over other apps" to show the chat '
          'overlay. Please enable it in Settings → Display over other apps.',
          style: TextStyle(color: Color(0xFFF0EFEB)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK', style: TextStyle(color: Color(0xFFFF2200))),
          ),
        ],
      ),
    );
  }

  // ── launcher gestures ─────────────────────────────────────────────────────

  void _launchSelected() {
    final items = _displayItems;
    if (_selSlot == null || items.isEmpty) return;
    final idx =
        ((_selSlot! + _offset) % items.length + items.length) % items.length;
    final item = items[idx];
    if (item is FolderEntry) {
      _showFolderPopup(item);
    } else if (item is AppEntry) {
      _AppLauncher.openApp(item.packageName);
      HapticFeedback.lightImpact();
    }
    setState(() {
      _open = false;
      _selSlot = null;
    });
    _ctrl.reverse();
  }

  void _toggle() {
    setState(() {
      _open = !_open;
      if (!_open) _selSlot = null;
    });
    _open ? _ctrl.forward() : _ctrl.reverse();
  }

  void _panStart(DragStartDetails d, Offset anchor) {
    if (!_open) return;
    _updateHover(d.localPosition, anchor, allowPaging: false);
  }

  void _pan(DragUpdateDetails d, Offset anchor) {
    if (!_open) return;
    _updateHover(d.localPosition, anchor);
  }

  void _panEnd(DragEndDetails d) {
    if (!_open) return;
    final vx = d.velocity.pixelsPerSecond.dx;
    if (vx.abs() < 650) {
      if (_selSlot != null) _launchSelected();
      return;
    }
    _nudge(
      vx > 0 ? _kVisibleAppCount : -_kVisibleAppCount,
      clearSelection: true,
    );
  }

  void _nudge(int d, {bool clearSelection = false}) {
    final total = _displayItems.length;
    if (total == 0) return;
    setState(() {
      _offset = ((_offset + d) % total + total) % total;
      if (clearSelection) _selSlot = null;
    });
  }

  void _pageByDrag(int d) {
    if (_pageStopwatch.elapsedMilliseconds < 220) return;
    _pageStopwatch.reset();
    _nudge(d, clearSelection: true);
  }

  void _updateHover(
    Offset localPosition,
    Offset anchor, {
    bool allowPaging = true,
  }) {
    final dx = localPosition.dx - anchor.dx;
    final dy = localPosition.dy - anchor.dy;
    final distSq = dx * dx + dy * dy;
    final ang = (math.atan2(dy, dx) + math.pi * 2) % (math.pi * 2);
    if (distSq < _kInnerR2 ||
        distSq > _kOuterR2 ||
        ang < _kArcStartRad ||
        ang > _kArcEndRad) {
      if (_selSlot != null) setState(() => _selSlot = null);
      return;
    }
    if (ang < _kMenuStartRad) {
      allowPaging ? _pageByDrag(-1) : _nudge(-1, clearSelection: true);
      return;
    }
    if (ang > _kMenuEndRad) {
      allowPaging ? _pageByDrag(1) : _nudge(1, clearSelection: true);
      return;
    }
    final total = _displayItems.length;
    final visible = math.min(_kVisibleAppCount, total);
    if (visible == 0) return;
    final slot = (((ang - _kMenuStartRad) / _kMenuSpanRad) * visible)
        .floor()
        .clamp(0, visible - 1);
    if (_selSlot != slot) setState(() => _selSlot = slot);
  }

  void _tap(TapDownDetails d, Offset anchor) {
    if (!_open) return;
    _updateHover(d.localPosition, anchor, allowPaging: false);
  }

  Offset _computeAnchor(BoxConstraints c) => Offset(
    math.max(
      _kOuterR + _kCornerInset,
      c.maxWidth - _kArcRightReach - _kCornerInset,
    ),
    c.maxHeight - _kHubR - _kCornerInset,
  );

  void _onWidgetsChanged() {
    if (_isEditing && _widgetHost.value.isEmpty) {
      if (mounted) setState(() => _isEditing = false);
    }
  }

  void _toggleEditMode() {
    setState(() {
      _isEditing = !_isEditing;
      if (_isEditing) {
        _editCtrl.repeat(reverse: true);
      } else {
        _editCtrl.stop();
        _editCtrl.reset();
      }
    });
  }

  void _reorderWidgets(int from, int to) {
    if (from == to) return;
    _widgetHost.move(from, to);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _editCtrl.dispose();
    _wallpaper.dispose();
    _widgetHost.removeListener(_onWidgetsChanged);
    _widgetHost.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: false,
      body: ListenableBuilder(
        listenable: _wallpaper,
        builder: (_, _) => Stack(
          children: [
            // ── wallpaper ──────────────────────────────────────────────
            if (_wallpaper.value != null)
              Positioned.fill(
                child: Image.memory(_wallpaper.value!, fit: BoxFit.cover),
              ),
            // ── dark scrim (improves readability over any wallpaper) ───
            Container(
              color: _wallpaper.value != null
                  ? Colors.black.withValues(alpha: 0)
                  : const Color(0xFF0D0D0D),
            ),
            // ── radial launcher ───────────────────────────────────────
            LayoutBuilder(
              builder: (_, c) {
                final anchor = _computeAnchor(c);
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    GestureDetector(
                      onLongPress: _showContextMenu,
                      onDoubleTap: _toggle,
                      onPanStart: (d) => _panStart(d, anchor),
                      onPanUpdate: (d) => _pan(d, anchor),
                      onPanEnd: _panEnd,
                      onTapDown: (d) => _tap(d, anchor),
                      onTap: () {
                        if (_open && _selSlot != null) _launchSelected();
                      },
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Positioned.fill(
                            child: FadeTransition(
                              opacity: _anim,
                              child: RepaintBoundary(
                                child: CustomPaint(
                                  painter: _Painter(
                                    anchor: anchor,
                                    items: _displayItems,
                                    offset: _offset,
                                    selectedSlot: _selSlot,
                                    appIconImages: _appIconImages,
                                    folderIconsList: _folderIcons,
                                  ),
                                  child: const SizedBox.expand(),
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            left: anchor.dx - _kHubR,
                            top: anchor.dy - _kHubR,
                            child: GestureDetector(
                              onDoubleTap: _toggle,
                              onLongPress: _startVoiceInput,
                              child: const _Hub(key: ValueKey('launcher-hub')),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
            // ── widget grid ─────────────────────────────────────────────
            ListenableBuilder(
              listenable: _widgetHost,
              builder: (_, _) => _buildWidgetGrid(),
            ),
          ],
        ),
      ),
    );
  }

  // ── context menu (long-press on empty area) ──────────────────────────

  void _showContextMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: ListView(
            shrinkWrap: true,
            children: [
              _MenuItem(
                icon: Icons.wallpaper_outlined,
                label: 'Set Wallpaper',
                onTap: () {
                  Navigator.pop(context);
                  _wallpaper.pickAndSet();
                },
              ),
              _MenuItem(
                icon: Icons.widgets_outlined,
                label: 'Add Widget',
                onTap: () {
                  Navigator.pop(context);
                  _addWidget();
                },
              ),
              _MenuItem(
                icon: _isEditing ? Icons.check : Icons.edit,
                label: _isEditing ? 'Done' : 'Edit Widgets',
                onTap: () {
                  Navigator.pop(context);
                  _toggleEditMode();
                },
              ),
              _MenuItem(
                icon: Icons.remove_circle_outline,
                label: 'Reset Wallpaper',
                onTap: () {
                  Navigator.pop(context);
                  _wallpaper.reset();
                },
              ),
              _MenuItem(
                icon: Icons.create_new_folder_outlined,
                label: 'Create Folder',
                onTap: () {
                  Navigator.pop(context);
                  _createFolder();
                },
              ),
              _MenuItem(
                icon: Icons.folder_outlined,
                label: 'Manage Folders',
                onTap: () {
                  Navigator.pop(context);
                  _manageFolders();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _addWidget() async {
    final providers = await _widgetHost.getProviders();
    if (!mounted || providers.isEmpty) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: ListView(
            shrinkWrap: true,
            children: List.generate(providers.length, (i) {
              final p = providers[i];
              return _MenuItem(
                icon: Icons.widgets_outlined,
                label: p.providerLabel,
                onTap: () async {
                  Navigator.pop(context);
                  try {
                    await _widgetHost.addWidget(
                      p.providerPackage,
                      p.providerClass,
                    );
                  } on WidgetHostException catch (e) {
                    _showLauncherSettingsDialog(e.code, e.message);
                  }
                },
              );
            }),
          ),
        ),
      ),
    );
  }

  void _confirmRemoveWidget(int appWidgetId, String label) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text(
          'Remove Widget',
          style: TextStyle(color: Color(0xFFF0EFEB)),
        ),
        content: Text(
          'Remove "$label"?',
          style: const TextStyle(color: Color(0xFFF0EFEB)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Color(0xFF888888)),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _widgetHost.remove(appWidgetId);
            },
            child: const Text(
              'Remove',
              style: TextStyle(color: Color(0xFFFF2200)),
            ),
          ),
        ],
      ),
    );
  }

  void _showLauncherSettingsDialog(String code, String message) {
    final title = switch (code) {
      'BIND_FAILED' => 'Widget Hosting Not Allowed',
      _ => 'Widget Error ($code)',
    };
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: Text(title, style: const TextStyle(color: Color(0xFFF0EFEB))),
        content: Text(
          message,
          style: const TextStyle(color: Color(0xFFF0EFEB)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Color(0xFF888888)),
            ),
          ),
          if (code == 'BIND_FAILED')
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                WranglNative.openHomeSettings();
              },
              child: const Text(
                'Open Settings',
                style: TextStyle(color: Color(0xFFFF5C35)),
              ),
            ),
        ],
      ),
    );
  }

  // ── folder popup ─────────────────────────────────────────────────────

  void _showFolderPopup(FolderEntry folder) {
    final pkgSet = folder.packageNames.toSet();
    final resolved = _apps
        .where((a) => pkgSet.contains(a.packageName))
        .toList();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
        title: Row(
          children: [
            Icon(
              _folderIcons[folder.iconIndex.clamp(0, _folderIcons.length - 1)],
              color: const Color(0xFFF0EFEB),
              size: 22,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                folder.name,
                style: const TextStyle(color: Color(0xFFF0EFEB), fontSize: 18),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: resolved.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      'Folder is empty',
                      style: TextStyle(color: Color(0xFF888888)),
                    ),
                  ),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: resolved.length,
                  separatorBuilder: (_, _) =>
                      const Divider(color: Color(0xFF333333), height: 1),
                  itemBuilder: (_, i) => ListTile(
                    dense: true,
                    leading: resolved[i].icon != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.memory(
                              resolved[i].icon!,
                              width: 28,
                              height: 28,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const Icon(
                                Icons.apps,
                                size: 24,
                                color: Color(0xFF888888),
                              ),
                            ),
                          )
                        : const Icon(
                            Icons.apps,
                            size: 24,
                            color: Color(0xFF888888),
                          ),
                    title: Text(
                      resolved[i].label,
                      style: const TextStyle(
                        color: Color(0xFFF0EFEB),
                        fontSize: 15,
                      ),
                    ),
                    onTap: () {
                      Navigator.of(ctx).pop();
                      _AppLauncher.openApp(resolved[i].packageName);
                      HapticFeedback.lightImpact();
                    },
                  ),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(
              'Close',
              style: TextStyle(color: Color(0xFFFF5C35)),
            ),
          ),
        ],
      ),
    );
  }

  // ── folder creation ──────────────────────────────────────────────────

  Future<void> _createFolder() async {
    final nameController = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
        title: const Text(
          'Folder Name',
          style: TextStyle(color: Color(0xFFF0EFEB)),
        ),
        content: TextField(
          controller: nameController,
          autofocus: true,
          style: const TextStyle(color: Color(0xFFF0EFEB)),
          decoration: const InputDecoration(
            hintText: 'e.g. Social',
            hintStyle: TextStyle(color: Color(0xFF666666)),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Color(0xFF555555)),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Color(0xFFFF5C35)),
            ),
          ),
          onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Color(0xFF888888)),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(nameController.text.trim()),
            child: const Text(
              'Next',
              style: TextStyle(color: Color(0xFFFF5C35)),
            ),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;
    final iconIdx = await _pickFolderIcon(null);
    if (iconIdx == null || !mounted) return;
    final pkgs = await _pickFolderApps(const []);
    if (pkgs == null || !mounted) return;
    setState(() {
      _folders = [..._folders, FolderEntry(name, pkgs, iconIndex: iconIdx)];
    });
    _saveFolders();
  }

  /// Shows a grid of preset folder icons. Returns the selected index or null if cancelled.
  /// [initial] is the currently selected index, or null for no selection.
  Future<int?> _pickFolderIcon(int? initial) async {
    return showDialog<int>(
      context: context,
      builder: (ctx) {
        var sel = initial;
        return StatefulBuilder(
          builder: (ctx, setInner) => AlertDialog(
            backgroundColor: const Color(0xFF1A1A1A),
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(16)),
            ),
            title: const Text(
              'Choose Folder Icon',
              style: TextStyle(color: Color(0xFFF0EFEB)),
            ),
            content: SizedBox(
              width: 280,
              height: 300,
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: _folderIcons.length,
                itemBuilder: (_, i) {
                  final selected = sel == i;
                  return GestureDetector(
                    onTap: () => setInner(() => sel = i),
                    child: Container(
                      decoration: BoxDecoration(
                        color: selected
                            ? const Color(0xFFFF5C35).withValues(alpha: 0.25)
                            : const Color(0xFF2A2A2A),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: selected
                              ? const Color(0xFFFF5C35)
                              : const Color(0xFF444444),
                          width: selected ? 2 : 1,
                        ),
                      ),
                      child: Icon(
                        _folderIcons[i],
                        color: selected
                            ? const Color(0xFFFF5C35)
                            : const Color(0xFFF0EFEB),
                        size: 28,
                      ),
                    ),
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text(
                  'Cancel',
                  style: TextStyle(color: Color(0xFF888888)),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(sel),
                child: const Text(
                  'Done',
                  style: TextStyle(color: Color(0xFFFF5C35)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Shows an app multi-select dialog. Returns list of chosen package names
  /// or null if cancelled.
  Future<List<String>?> _pickFolderApps(List<String> initialPkgs) async {
    final selected = Set<String>.from(initialPkgs);
    final sorted = List<AppEntry>.from(_apps)
      ..sort((a, b) => a.label.compareTo(b.label));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInnerState) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(16)),
          ),
          title: const Text(
            'Select Apps',
            style: TextStyle(color: Color(0xFFF0EFEB)),
          ),
          content: SizedBox(
            width: double.maxFinite,
            height: 400,
            child: ListView.builder(
              itemCount: sorted.length,
              itemBuilder: (_, i) => CheckboxListTile(
                dense: true,
                value: selected.contains(sorted[i].packageName),
                secondary: sorted[i].icon != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.memory(
                          sorted[i].icon!,
                          width: 24,
                          height: 24,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Icon(
                            Icons.apps,
                            size: 22,
                            color: Color(0xFF888888),
                          ),
                        ),
                      )
                    : const Icon(
                        Icons.apps,
                        size: 22,
                        color: Color(0xFF888888),
                      ),
                title: Text(
                  sorted[i].label,
                  style: const TextStyle(
                    color: Color(0xFFF0EFEB),
                    fontSize: 14,
                  ),
                ),
                activeColor: const Color(0xFFFF5C35),
                checkColor: Colors.white,
                onChanged: (v) {
                  setInnerState(() {
                    if (v == true) {
                      selected.add(sorted[i].packageName);
                    } else {
                      selected.remove(sorted[i].packageName);
                    }
                  });
                },
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text(
                'Cancel',
                style: TextStyle(color: Color(0xFF888888)),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text(
                'Done',
                style: TextStyle(color: Color(0xFFFF5C35)),
              ),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return null;
    return selected.toList();
  }

  // ── folder management ────────────────────────────────────────────────

  void _manageFolders() {
    if (_folders.isEmpty) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(16)),
          ),
          title: const Text(
            'No Folders',
            style: TextStyle(color: Color(0xFFF0EFEB)),
          ),
          content: const Text(
            'Tap "Create Folder" to make your first folder.',
            style: TextStyle(color: Color(0xFF888888)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text(
                'OK',
                style: TextStyle(color: Color(0xFFFF5C35)),
              ),
            ),
          ],
        ),
      );
      return;
    }
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Text(
                  '${_folders.length} folder${_folders.length == 1 ? '' : 's'}',
                  style: const TextStyle(
                    color: Color(0xFF888888),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              ...List.generate(_folders.length, (i) {
                final f = _folders[i];
                final count = f.packageNames.length;
                return ListTile(
                  leading: Icon(
                    _folderIcons[f.iconIndex.clamp(0, _folderIcons.length - 1)],
                    color: const Color(0xFFF0EFEB),
                    size: 22,
                  ),
                  title: Text(
                    f.name,
                    style: const TextStyle(
                      color: Color(0xFFF0EFEB),
                      fontSize: 15,
                    ),
                  ),
                  subtitle: Text(
                    '$count app${count == 1 ? '' : 's'}',
                    style: const TextStyle(
                      color: Color(0xFF888888),
                      fontSize: 12,
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(
                          Icons.edit_outlined,
                          color: Color(0xFFF0EFEB),
                          size: 20,
                        ),
                        onPressed: () {
                          Navigator.pop(context);
                          _editFolder(i);
                        },
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.delete_outline,
                          color: Color(0xFFFF2200),
                          size: 20,
                        ),
                        onPressed: () {
                          Navigator.pop(context);
                          _deleteFolder(i);
                        },
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _editFolder(int index) async {
    final folder = _folders[index];
    final nameController = TextEditingController(text: folder.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
        title: const Text(
          'Rename Folder',
          style: TextStyle(color: Color(0xFFF0EFEB)),
        ),
        content: TextField(
          controller: nameController,
          autofocus: true,
          style: const TextStyle(color: Color(0xFFF0EFEB)),
          decoration: const InputDecoration(
            hintText: 'Folder name',
            hintStyle: TextStyle(color: Color(0xFF666666)),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Color(0xFF555555)),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Color(0xFFFF5C35)),
            ),
          ),
          onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Color(0xFF888888)),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(nameController.text.trim()),
            child: const Text(
              'Next',
              style: TextStyle(color: Color(0xFFFF5C35)),
            ),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;
    final iconIdx = await _pickFolderIcon(folder.iconIndex);
    if (iconIdx == null || !mounted) return;
    final pkgs = await _pickFolderApps(folder.packageNames);
    if (pkgs == null || !mounted) return;
    setState(() {
      _folders = [
        for (int i = 0; i < _folders.length; i++)
          if (i == index)
            FolderEntry(name, pkgs, iconIndex: iconIdx)
          else
            _folders[i],
      ];
    });
    _saveFolders();
  }

  Future<void> _deleteFolder(int index) async {
    final folder = _folders[index];
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
        title: const Text(
          'Delete Folder',
          style: TextStyle(color: Color(0xFFF0EFEB)),
        ),
        content: Text(
          'Delete "${folder.name}"? The apps inside will reappear in your launcher.',
          style: const TextStyle(color: Color(0xFFF0EFEB)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Color(0xFF888888)),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              'Delete',
              style: TextStyle(color: Color(0xFFFF2200)),
            ),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() {
      _folders = [
        for (int i = 0; i < _folders.length; i++)
          if (i != index) _folders[i],
      ];
    });
    _saveFolders();
  }

  // ── widget grid rendering ───────────────────────────────────────────

  Widget _buildWidgetGrid() {
    final widgets = _widgetHost.value;
    if (widgets.isEmpty) {
      if (_isEditing) {
        Future.microtask(() {
          if (mounted) setState(() => _isEditing = false);
        });
      }
      return const SizedBox.shrink();
    }

    return Positioned.fill(
      child: Padding(
        padding: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top + 8,
          left: 8,
          right: 8,
          bottom: _kHubR * 2 + _kCornerInset + 60,
        ),
        child: LayoutBuilder(
          builder: (_, c) => Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(widgets.length, (i) {
              final w = widgets[i];
              final tile = _WidgetTile(
                entry: w,
                isEditing: _isEditing,
                jiggleAnim: _editAnim,
                onRemove: () =>
                    _confirmRemoveWidget(w.appWidgetId, w.providerLabel),
              );
              if (!_isEditing) return tile;
              return LongPressDraggable<int>(
                data: i,
                feedback: Material(
                  borderRadius: BorderRadius.circular(16),
                  elevation: 8,
                  child: tile,
                ),
                childWhenDragging: tile,
                child: DragTarget<int>(
                  onAcceptWithDetails: (d) {
                    if (d.data != i) _reorderWidgets(d.data, i);
                  },
                  builder: (_, __, ___) => tile,
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

// ─── Context menu item tile ────────────────────────────────────────────────

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _MenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon, color: const Color(0xFFF0EFEB), size: 22),
    title: Text(
      label,
      style: const TextStyle(color: Color(0xFFF0EFEB), fontSize: 15),
    ),
    onTap: onTap,
    dense: true,
  );
}

// ─── Widget tile ───────────────────────────────────────────────────────────

class _WidgetTile extends StatelessWidget {
  final WidgetHostEntry entry;
  final bool isEditing;
  final Animation<double> jiggleAnim;
  final VoidCallback onRemove;

  const _WidgetTile({
    required this.entry,
    required this.isEditing,
    required this.jiggleAnim,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final double w = entry.minWidthDp.toDouble();
    final double h = entry.minHeightDp.toDouble();

    final tileBody = Container(
      width: w,
      height: h,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: isEditing
          ? Stack(
              clipBehavior: Clip.none,
              children: [
                AndroidView(
                  viewType: 'com.wrangl/widget_host',
                  creationParams: {'appWidgetId': entry.appWidgetId},
                  creationParamsCodec: const StandardMessageCodec(),
                ),
                Positioned(
                  top: 4,
                  right: 4,
                  child: GestureDetector(
                    onTap: onRemove,
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: const BoxDecoration(
                        color: Color(0x88000000),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.close,
                        color: Colors.white,
                        size: 14,
                      ),
                    ),
                  ),
                ),
              ],
            )
          : AndroidView(
              viewType: 'com.wrangl/widget_host',
              creationParams: {'appWidgetId': entry.appWidgetId},
              creationParamsCodec: const StandardMessageCodec(),
            ),
    );

    if (!isEditing) return tileBody;

    final phase =
        (entry.appWidgetId % 2 == 0 ? 1 : -1) *
        (1 + (entry.appWidgetId % 5) * 0.1);
    return AnimatedBuilder(
      animation: jiggleAnim,
      builder: (context, child) =>
          Transform.rotate(angle: jiggleAnim.value * phase, child: child),
      child: tileBody,
    );
  }
}

// ─── Hub ────────────────────────────────────────────────────────────────────

class _Hub extends StatelessWidget {
  const _Hub({super.key});

  @override
  Widget build(BuildContext context) => Container(
    width: _kHubR * 2,
    height: _kHubR * 2,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: const Color(0xFF5C5C5C),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.5),
          blurRadius: 20 * _kLauncherScale,
          spreadRadius: 4 * _kLauncherScale,
        ),
      ],
    ),
  );
}

// ─── Painter ─────────────────────────────────────────────────────────────────

class _LabelLayout {
  final String label;
  final bool isFolder;
  final int slot;
  final double midRad;
  final Offset center;
  final TextPainter painter;
  final ui.Image? appIcon;
  final IconData? folderIcon;

  const _LabelLayout({
    required this.label,
    required this.isFolder,
    required this.slot,
    required this.midRad,
    required this.center,
    required this.painter,
    this.appIcon,
    this.folderIcon,
  });
}

class _Painter extends CustomPainter {
  static final Paint _dividerPaint = Paint()
    ..color = const Color(0xFF555555)
    ..strokeWidth = 4.5 * _kLauncherScale
    ..strokeCap = StrokeCap.round;
  static final Paint _previewShadowPaint = Paint()
    ..color = Colors.black.withValues(alpha: 0.35)
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8 * _kLauncherScale);
  static final Paint _previewFillPaint = Paint()
    ..color = const Color(0xFFD9D9D9);
  static final Paint _bgShadowPaint = Paint()
    ..color = Colors.black.withValues(alpha: 0.4)
    ..maskFilter = const MaskFilter.blur(
      BlurStyle.normal,
      10 * _kLauncherScale,
    );
  static final Paint _bgFillPaint = Paint()..color = const Color(0xFFD9D9D9);
  static final Paint _selectionGlowPaint = Paint()
    ..color = const Color(0xFFFF5C35).withValues(alpha: 0.25)
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8 * _kLauncherScale);
  static final Paint _selectionFillPaint = Paint()
    ..color = const Color(0xFFFF5C35).withValues(alpha: 0.6);
  static final Paint _folderSegmentPaint = Paint()
    ..color = const Color(0xFF5C5C5C);
  static final Path _previewTabPath = _buildPreviewTabPath();
  static const double _iconSize = 14.0;
  static const double _iconTextGap = 3.0;

  final Offset anchor;
  final List<Object> items;
  final int offset;
  final int? selectedSlot;
  final Map<String, ui.Image> appIconImages;
  final List<IconData> folderIconsList;

  late final int _visible;
  late final double _segRad;
  late final Path _bgPath;
  late final Path? _selectionPath;
  late final List<_LabelLayout> _labels;
  late final _LabelLayout? _selectedLabel;
  late final TextPainter? _previewPainter;
  late final Set<int> _folderSlots;

  _Painter({
    required this.anchor,
    required this.items,
    required this.offset,
    required this.selectedSlot,
    required this.appIconImages,
    required this.folderIconsList,
  }) {
    _visible = math.min(_kVisibleAppCount, items.length);
    _segRad = _visible == 0 ? 0 : _kMenuSpanRad / _visible;
    _bgPath = _buildCrescentPath(anchor);
    _folderSlots = <int>{};
    _labels = _buildLabels();
    _selectedLabel =
        selectedSlot != null &&
            selectedSlot! >= 0 &&
            selectedSlot! < _labels.length
        ? _labels[selectedSlot!]
        : null;
    _selectionPath = _selectedLabel == null
        ? null
        : _buildSelectionPath(_selectedLabel.slot);
    _previewPainter = _selectedLabel == null
        ? null
        : _createPreviewPainter(_selectedLabel.label);
  }

  static Offset _pointFor(Offset anchor, double radius, double angle) => Offset(
    anchor.dx + radius * math.cos(angle),
    anchor.dy + radius * math.sin(angle),
  );

  static Path _buildPreviewTabPath() {
    final tabStart = _kOuterR - 20 * _kLauncherScale;
    final tabLength = 122 * _kLauncherScale;
    final tabWidth = 52 * _kLauncherScale;
    final tabRadius = 13 * _kLauncherScale;
    final flare = 22 * _kLauncherScale;
    final neckWidth = tabWidth * 0.62;
    final tabEnd = tabStart + tabLength;
    return Path()
      ..moveTo(tabStart, -neckWidth / 2)
      ..quadraticBezierTo(
        tabStart + flare * 0.35,
        -tabWidth / 2,
        tabStart + flare,
        -tabWidth / 2,
      )
      ..lineTo(tabEnd - tabRadius, -tabWidth / 2)
      ..quadraticBezierTo(
        tabEnd,
        -tabWidth / 2,
        tabEnd,
        -tabWidth / 2 + tabRadius,
      )
      ..lineTo(tabEnd, tabWidth / 2 - tabRadius)
      ..quadraticBezierTo(
        tabEnd,
        tabWidth / 2,
        tabEnd - tabRadius,
        tabWidth / 2,
      )
      ..lineTo(tabStart + flare * 0.75, tabWidth / 2)
      ..quadraticBezierTo(
        tabStart + flare * 0.15,
        tabWidth / 2,
        tabStart,
        neckWidth / 2,
      )
      ..close();
  }

  static Path _buildCrescentPath(Offset anchor) {
    const cornerR = 14 * _kLauncherScale;
    const outerDelta = cornerR / _kOuterR;
    const innerDelta = cornerR / _kInnerR;
    final path = Path();
    final outerRect = Rect.fromCircle(center: anchor, radius: _kOuterR);
    final innerRect = Rect.fromCircle(center: anchor, radius: _kInnerR);
    final sOA = _pointFor(anchor, _kOuterR, _kArcStartRad + outerDelta);
    final sO = _pointFor(anchor, _kOuterR, _kArcStartRad);
    final sI = _pointFor(anchor, _kInnerR, _kArcStartRad);
    final eO = _pointFor(anchor, _kOuterR, _kArcEndRad);
    final eI = _pointFor(anchor, _kInnerR, _kArcEndRad);
    final eOC = _pointFor(anchor, _kOuterR - cornerR, _kArcEndRad);
    final eIC = _pointFor(anchor, _kInnerR + cornerR, _kArcEndRad);
    final eIA = _pointFor(anchor, _kInnerR, _kArcEndRad - innerDelta);
    final sIC = _pointFor(anchor, _kInnerR + cornerR, _kArcStartRad);
    final sOC = _pointFor(anchor, _kOuterR - cornerR, _kArcStartRad);
    path
      ..moveTo(sOA.dx, sOA.dy)
      ..arcTo(
        outerRect,
        _kArcStartRad + outerDelta,
        _kArcSpanRad - 2 * outerDelta,
        false,
      )
      ..quadraticBezierTo(eO.dx, eO.dy, eOC.dx, eOC.dy)
      ..lineTo(eIC.dx, eIC.dy)
      ..quadraticBezierTo(eI.dx, eI.dy, eIA.dx, eIA.dy)
      ..arcTo(
        innerRect,
        _kArcEndRad - innerDelta,
        -(_kArcSpanRad - 2 * innerDelta),
        false,
      )
      ..quadraticBezierTo(sI.dx, sI.dy, sIC.dx, sIC.dy)
      ..lineTo(sOC.dx, sOC.dy)
      ..quadraticBezierTo(sO.dx, sO.dy, sOA.dx, sOA.dy)
      ..close();
    return path;
  }

  Offset _point(double radius, double angle) =>
      _pointFor(anchor, radius, angle);

  Offset _tangentPoint(double radius, double tangentOffset, double angle) =>
      Offset(
        anchor.dx +
            radius * math.cos(angle) +
            tangentOffset * math.cos(angle + math.pi / 2),
        anchor.dy +
            radius * math.sin(angle) +
            tangentOffset * math.sin(angle + math.pi / 2),
      );

  double _towardTopLean(double angle) {
    const top = math.pi * 1.5;
    var delta = top - angle;
    while (delta > math.pi) delta -= math.pi * 2;
    while (delta < -math.pi) delta += math.pi * 2;
    return delta.clamp(-0.28, 0.28) * 0.45;
  }

  String _labelOf(Object item) {
    if (item is AppEntry) return item.label;
    if (item is FolderEntry) return item.name;
    return '';
  }

  List<_LabelLayout> _buildLabels() {
    if (_visible == 0) return const [];
    final labels = <_LabelLayout>[];
    final midR = (_kInnerR + _kOuterR) / 2;
    for (int i = 0; i < _visible; i++) {
      final idx = ((i + offset) % items.length + items.length) % items.length;
      final item = items[idx];
      final isFolder = item is FolderEntry;
      final isSelected = selectedSlot == i;
      if (isFolder) _folderSlots.add(i);
      final midRad = _kMenuStartRad + (i + 0.5) * _segRad;
      final textMaxWidth =
          72 * _kLabelScale - _iconSize * _kLabelScale - _iconTextGap;
      final painter = TextPainter(
        text: TextSpan(
          text: _labelOf(item),
          style: TextStyle(
            fontSize: (isSelected ? 10.5 : 9.5) * _kLabelScale,
            fontWeight: FontWeight.w700,
            color: isSelected
                ? Colors.white
                : (isFolder ? Colors.white : const Color(0xFF1A1A1A)),
            letterSpacing: 0,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: textMaxWidth.clamp(40, 120));
      final appIcon = item is AppEntry ? appIconImages[item.packageName] : null;
      final folderIcon = item is FolderEntry
          ? folderIconsList[item.iconIndex.clamp(0, folderIconsList.length - 1)]
          : null;
      labels.add(
        _LabelLayout(
          label: _labelOf(item),
          isFolder: isFolder,
          slot: i,
          midRad: midRad,
          center: _point(midR, midRad),
          painter: painter,
          appIcon: appIcon,
          folderIcon: folderIcon,
        ),
      );
    }
    return labels;
  }

  TextPainter _createPreviewPainter(String label) => TextPainter(
    text: TextSpan(
      text: label,
      style: TextStyle(
        fontSize: 15.5 * _kLabelScale,
        fontWeight: FontWeight.w700,
        color: const Color(0xFF1A1A1A),
        letterSpacing: 0,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: 84 * _kLabelScale);

  Path _buildSelectionPath(int slot) {
    final segS = _kMenuStartRad + slot * _segRad;
    return Path()
      ..moveTo(anchor.dx, anchor.dy)
      ..addArc(
        Rect.fromCircle(
          center: anchor,
          radius: _kOuterR + 10 * _kLauncherScale,
        ),
        segS,
        _segRad,
      )
      ..lineTo(anchor.dx, anchor.dy);
  }

  Path _buildFolderSegmentPath(int slot) {
    final segS = _kMenuStartRad + slot * _segRad;
    return Path()
      ..moveTo(anchor.dx, anchor.dy)
      ..addArc(Rect.fromCircle(center: anchor, radius: _kOuterR), segS, _segRad)
      ..lineTo(anchor.dx, anchor.dy);
  }

  void _drawDivider(Canvas canvas, double rad) {
    canvas.drawLine(
      _point(_kInnerR + 8 * _kLauncherScale, rad),
      _point(_kOuterR - 14 * _kLauncherScale, rad),
      _dividerPaint,
    );
  }

  void _drawPreview(Canvas canvas, _LabelLayout sel, TextPainter pp) {
    final rad = sel.midRad + _towardTopLean(sel.midRad);
    canvas.save();
    canvas.translate(anchor.dx, anchor.dy);
    canvas.rotate(rad);
    canvas.drawPath(_previewTabPath, _previewShadowPaint);
    canvas.drawPath(_previewTabPath, _previewFillPaint);
    canvas.restore();
    final tc = _tangentPoint(
      _kOuterR + 40 * _kLauncherScale,
      2 * _kLauncherScale,
      rad,
    );
    canvas.save();
    canvas.translate(tc.dx, tc.dy);
    canvas.rotate(rad + math.pi);
    final preIconSize = 18.0 * _kLauncherScale;
    final preGap = 4.0 * _kLauncherScale;
    final textX = -pp.width / 2;
    final textY = -pp.height / 2;
    if (sel.appIcon != null) {
      final img = sel.appIcon!;
      canvas.drawImageRect(
        img,
        Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
        Rect.fromLTWH(
          textX - preIconSize - preGap,
          textY + (pp.height - preIconSize) / 2,
          preIconSize,
          preIconSize,
        ),
        Paint()..filterQuality = FilterQuality.low,
      );
    } else if (sel.folderIcon != null) {
      final iconPainter = TextPainter(
        text: TextSpan(
          text: String.fromCharCode(sel.folderIcon!.codePoint),
          style: TextStyle(
            fontFamily: 'MaterialIcons',
            fontSize: preIconSize,
            color: const Color(0xFF1A1A1A),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      iconPainter.paint(
        canvas,
        Offset(
          textX - preIconSize - preGap,
          textY + (pp.height - preIconSize) / 2,
        ),
      );
    }
    pp.paint(canvas, Offset(textX, textY));
    canvas.restore();
  }

  void _drawLabelWithIcon(Canvas canvas, _LabelLayout label) {
    canvas.save();
    canvas.translate(label.center.dx, label.center.dy);
    canvas.rotate(label.midRad + math.pi);

    final textOffset = Offset(
      -label.painter.width / 2,
      -label.painter.height / 2,
    );
    final scaledIcon = _iconSize * _kLauncherScale;

    if (label.appIcon != null) {
      final img = label.appIcon!;
      final srcW = img.width.toDouble();
      final srcH = img.height.toDouble();
      final iconX = textOffset.dx - scaledIcon - _iconTextGap;
      final iconY = textOffset.dy + (label.painter.height - scaledIcon) / 2;
      canvas.drawImageRect(
        img,
        Rect.fromLTWH(0, 0, srcW, srcH),
        Rect.fromLTWH(iconX, iconY, scaledIcon, scaledIcon),
        Paint()..filterQuality = FilterQuality.low,
      );
    } else if (label.folderIcon != null) {
      final iconPainter = TextPainter(
        text: TextSpan(
          text: String.fromCharCode(label.folderIcon!.codePoint),
          style: TextStyle(
            fontFamily: 'MaterialIcons',
            fontSize: scaledIcon,
            color: label.isFolder && label.slot == (selectedSlot ?? -1)
                ? Colors.white
                : const Color(0xFFFFFFFF),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final iconX = textOffset.dx - scaledIcon - _iconTextGap;
      final iconY = textOffset.dy + (label.painter.height - scaledIcon) / 2;
      iconPainter.paint(canvas, Offset(iconX, iconY));
    }

    label.painter.paint(canvas, textOffset);
    canvas.restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (_visible == 0) return;
    canvas.drawPath(_bgPath, _bgShadowPaint);
    canvas.drawPath(_bgPath, _bgFillPaint);
    canvas.save();
    canvas.clipPath(_bgPath);
    for (final slot in _folderSlots) {
      if (slot == selectedSlot) continue;
      canvas.drawPath(_buildFolderSegmentPath(slot), _folderSegmentPaint);
    }
    if (_selectionPath != null) {
      final selIsFolder = _selectedLabel!.isFolder;
      canvas.drawPath(_selectionPath, _selectionGlowPaint);
      canvas.drawPath(
        _selectionPath,
        selIsFolder ? _folderSegmentPaint : _selectionFillPaint,
      );
    }
    canvas.restore();
    _drawDivider(canvas, _kMenuStartRad);
    _drawDivider(canvas, _kMenuEndRad);
    for (final label in _labels) {
      _drawLabelWithIcon(canvas, label);
    }
    if (_selectedLabel != null && _previewPainter != null) {
      _drawPreview(canvas, _selectedLabel, _previewPainter);
    }
  }

  @override
  bool shouldRepaint(covariant _Painter old) =>
      old.anchor != anchor ||
      old.items != items ||
      old.offset != offset ||
      old.selectedSlot != selectedSlot ||
      old.appIconImages != appIconImages ||
      old.folderIconsList != folderIconsList;
}
