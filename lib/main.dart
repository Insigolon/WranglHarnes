import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:wrangl_native/wrangl_native.dart';
import 'agent/model_config.dart';
import 'overlay/bubble_overlay.dart';
import 'screens/model_download_screen.dart';
import 'src/rust/api/simple.dart';
import 'src/rust/frb_generated.dart';

class _AppLauncher {
  static Future<List<AppEntry>> getInstalledApps() async {
    final raw = await WranglNative.getInstalledApps();
    return raw
        .map((m) => AppEntry(m['packageName']!, m['label']!))
        .toList();
  }

  static Future<void> openApp(String packageName) => WranglNative.launchApp(packageName);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Bring up the Rust core (flutter_rust_bridge). This must run once per
  // isolate that calls into Rust. Validates the FFI toolchain end-to-end.
  await RustLib.init();
  debugPrint('[rust] ${greet(name: "Wrangl")}');

  // The model file is loaded inside the overlay isolate, not here — the main
  // isolate only needs to know whether it has already been downloaded.
  final path = await ModelConfig.path();
  final file = File(path);
  final modelReady =
      await file.exists() && await file.length() > 100 * 1024 * 1024;

  runApp(MyApp(modelReady: modelReady));
}

/// Entry point for the overlay isolate spawned by flutter_overlay_window.
/// The native side launches the Dart function named exactly `overlayMain`.
@pragma('vm:entry-point')
void overlayMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The overlay isolate uses the Rust harness too, so init the bridge here.
  await RustLib.init();
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
  const AppEntry(this.packageName, this.label);
}

// ─── Launcher constants ──────────────────────────────────────────────────────
const double _kArcStart = 160.0;
const double _kArcEnd = 290.0;
const double _kLauncherScale = 1.28;
const double _kLabelScale = 1.55;
const double _kHubR = 46.0 * _kLauncherScale;
const double _kInnerR = 72.0 * _kLauncherScale;
const double _kOuterR = 148.0 * _kLauncherScale;
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
    with TickerProviderStateMixin, WidgetsBindingObserver {
  // launcher state
  bool _open = false;
  int? _selSlot;
  int _offset = 0;
  List<AppEntry> _apps = const [];
  bool _screenReady = false; // MediaProjection consent granted + service live
  bool _overlayPermAsked = false; // ask the system overlay perm at most once per session
  final Stopwatch _pageStopwatch = Stopwatch()..start();

  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
  );
  late final Animation<double> _anim = CurvedAnimation(
    parent: _ctrl,
    curve: Curves.easeOutCubic,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadApps();
    _ensureBubble(requestIfNeeded: true);
    _refreshScreenReady();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // On resume we only *show* the bubble if perm is already granted — we
    // never re-fire requestPermission here, because returning from the system
    // settings page itself triggers resumed, which would create a redirect
    // loop that locks the user on the "Display over other apps" screen.
    if (state == AppLifecycleState.resumed) {
      _ensureBubble();
      _refreshScreenReady();
    }
  }

  // ── screen access (MediaProjection, consent timing A) ──────────────────────

  Future<void> _refreshScreenReady() async {
    final ready = await WranglNative.isScreenReady();
    if (mounted) setState(() => _screenReady = ready);
  }

  Future<void> _toggleScreenAccess() async {
    HapticFeedback.lightImpact();
    if (_screenReady) {
      await WranglNative.stopScreen();
    } else {
      await WranglNative.requestScreenConsent();
    }
    await _refreshScreenReady();
  }

  Future<void> _loadApps() async {
    final entries = await _AppLauncher.getInstalledApps();
    if (mounted) setState(() => _apps = entries);
  }

  // ── floating system bubble ─────────────────────────────────────────────────

  /// Make sure the draw-over-other-apps bubble is running. Only fires
  /// requestPermission when [requestIfNeeded] is true AND we haven't already
  /// asked this session — otherwise auto-callers (resume) would re-open the
  /// settings page every time the user returns to the app, trapping them.
  Future<void> _ensureBubble({bool requestIfNeeded = false}) async {
    if (await FlutterOverlayWindow.isActive()) return;
    if (!await FlutterOverlayWindow.isPermissionGranted()) {
      if (requestIfNeeded && !_overlayPermAsked) {
        _overlayPermAsked = true;
        await FlutterOverlayWindow.requestPermission();
      }
      return; // wait until the user grants it; resumed will show it then
    }
    await FlutterOverlayWindow.showOverlay(
      height: kBubbleWindow.toInt(),
      width: kBubbleWindow.toInt(),
      alignment: OverlayAlignment.centerRight,
      flag: OverlayFlag.defaultFlag,
      enableDrag: true,
      positionGravity: PositionGravity.auto,
      overlayTitle: 'Wrangl',
      overlayContent: 'Tap the bubble to chat',
    );
  }

  // ── launcher gestures ─────────────────────────────────────────────────────

  void _launchSelected() {
    if (_selSlot == null || _apps.isEmpty) return;
    final idx =
        ((_selSlot! + _offset) % _apps.length + _apps.length) % _apps.length;
    _AppLauncher.openApp(_apps[idx].packageName);
    HapticFeedback.lightImpact();
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
    final total = _apps.length;
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
    final total = _apps.length;
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

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        backgroundColor: const Color(0xFF0D0D0D),
        resizeToAvoidBottomInset: false,
        body: LayoutBuilder(
          builder: (_, c) {
            final anchor = _computeAnchor(c);
            return Stack(
              clipBehavior: Clip.none,
              children: [
                // ── radial launcher ──────────────────────────────────
                GestureDetector(
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
                                apps: _apps,
                                offset: _offset,
                                selectedSlot: _selSlot,
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
                          // The floating system bubble is the chat entry point
                          // now; long-press re-arms it (and may re-ask the
                          // overlay permission if the user denied it earlier).
                          onLongPress: () {
                            _overlayPermAsked = false;
                            _ensureBubble(requestIfNeeded: true);
                          },
                          child: const _Hub(key: ValueKey('launcher-hub')),
                        ),
                      ),
                    ],
                  ),
                ),

                // ── screen-access opt-in (lets the bubble see other apps) ──
                Positioned(
                  top: MediaQuery.of(context).padding.top + 12,
                  left: 16,
                  child: _ScreenAccessChip(
                    enabled: _screenReady,
                    onTap: _toggleScreenAccess,
                  ),
                ),
              ],
            );
          },
        ),
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

// ─── Screen-access chip ───────────────────────────────────────────────────────

class _ScreenAccessChip extends StatelessWidget {
  final bool enabled;
  final VoidCallback onTap;
  const _ScreenAccessChip({required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final accent = enabled ? const Color(0xFFFF2200) : const Color(0xFF666666);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: accent.withValues(alpha: 0.6)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Text(
              enabled ? 'SCREEN ACCESS ON' : 'ENABLE SCREEN ACCESS',
              style: const TextStyle(
                color: Color(0xFFF0EFEB),
                fontSize: 9,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Painter (unchanged) ─────────────────────────────────────────────────────

class _LabelLayout {
  final AppEntry app;
  final int slot;
  final double midRad;
  final Offset center;
  final TextPainter painter;

  const _LabelLayout({
    required this.app,
    required this.slot,
    required this.midRad,
    required this.center,
    required this.painter,
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
  static final Path _previewTabPath = _buildPreviewTabPath();

  final Offset anchor;
  final List<AppEntry> apps;
  final int offset;
  final int? selectedSlot;

  late final int _visible;
  late final double _segRad;
  late final Path _bgPath;
  late final Path? _selectionPath;
  late final List<_LabelLayout> _labels;
  late final _LabelLayout? _selectedLabel;
  late final TextPainter? _previewPainter;

  _Painter({
    required this.anchor,
    required this.apps,
    required this.offset,
    required this.selectedSlot,
  }) {
    _visible = math.min(_kVisibleAppCount, apps.length);
    _segRad = _visible == 0 ? 0 : _kMenuSpanRad / _visible;
    _bgPath = _buildCrescentPath(anchor);
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
        : _createPreviewPainter(_selectedLabel.app);
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

  List<_LabelLayout> _buildLabels() {
    if (_visible == 0) return const [];
    final labels = <_LabelLayout>[];
    final midR = (_kInnerR + _kOuterR) / 2;
    for (int i = 0; i < _visible; i++) {
      final idx = ((i + offset) % apps.length + apps.length) % apps.length;
      final app = apps[idx];
      final isSelected = selectedSlot == i;
      final midRad = _kMenuStartRad + (i + 0.5) * _segRad;
      final painter = TextPainter(
        text: TextSpan(
          text: app.label,
          style: TextStyle(
            fontSize: (isSelected ? 10.5 : 9.5) * _kLabelScale,
            fontWeight: FontWeight.w700,
            color: isSelected ? Colors.white : const Color(0xFF1A1A1A),
            letterSpacing: 0,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 72 * _kLabelScale);
      labels.add(
        _LabelLayout(
          app: app,
          slot: i,
          midRad: midRad,
          center: _point(midR, midRad),
          painter: painter,
        ),
      );
    }
    return labels;
  }

  TextPainter _createPreviewPainter(AppEntry app) => TextPainter(
    text: TextSpan(
      text: app.label,
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
    pp.paint(canvas, Offset(-pp.width / 2, -pp.height / 2));
    canvas.restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (_visible == 0) return;
    canvas.drawPath(_bgPath, _bgShadowPaint);
    canvas.drawPath(_bgPath, _bgFillPaint);
    canvas.save();
    canvas.clipPath(_bgPath);
    if (_selectionPath != null) {
      canvas.drawPath(_selectionPath, _selectionGlowPaint);
      canvas.drawPath(_selectionPath, _selectionFillPaint);
    }
    canvas.restore();
    _drawDivider(canvas, _kMenuStartRad);
    _drawDivider(canvas, _kMenuEndRad);
    for (final label in _labels) {
      canvas.save();
      canvas.translate(label.center.dx, label.center.dy);
      canvas.rotate(label.midRad + math.pi);
      label.painter.paint(
        canvas,
        Offset(-label.painter.width / 2, -label.painter.height / 2),
      );
      canvas.restore();
    }
    if (_selectedLabel != null && _previewPainter != null) {
      _drawPreview(canvas, _selectedLabel, _previewPainter);
    }
  }

  @override
  bool shouldRepaint(covariant _Painter old) =>
      old.anchor != anchor ||
      old.apps != apps ||
      old.offset != offset ||
      old.selectedSlot != selectedSlot;
}
