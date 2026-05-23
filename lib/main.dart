import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:provider/provider.dart';
import 'agent/agent_provider.dart';
import 'screens/agent_chat_screen.dart';
import 'screens/model_download_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FlutterGemma.initialize();
  runApp(
    ChangeNotifierProvider(
      create: (_) => AgentProvider(),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: ModelDownloadScreen(),
    );
  }
}

class AppEntry {
  final String id, label;
  const AppEntry(this.id, this.label);
}

const _kApps = [
  AppEntry('a', 'Claude'),
  AppEntry('b', 'Whatsapp'),
  AppEntry('c', 'Phone'),
  AppEntry('d', 'Brave'),
  AppEntry('e', 'Instagram'),
  AppEntry('f', 'Maps'),
  AppEntry('g', 'Twitter'),
  AppEntry('h', 'Duolingo'),
  AppEntry('i', 'Drive'),
  AppEntry('j', 'Gmail'),
  AppEntry('k', 'Spotify'),
  AppEntry('l', 'YouTube'),
];

const double _kArcStart = 205.0;
const double _kArcEnd = 335.0;
const double _kLauncherScale = 1.28;
const double _kLabelScale = 1.55;
const double _kHubR = 46.0 * _kLauncherScale;
const double _kInnerR = 72.0 * _kLauncherScale;
const double _kOuterR = 148.0 * _kLauncherScale;
const double _kCornerInset = 12.0 * _kLauncherScale;
const double _kButtonSweep = 18.0;
const double _kMenuStart = _kArcStart + _kButtonSweep;
const double _kMenuEnd = _kArcEnd - _kButtonSweep;
const int _kVisibleAppCount = 9;

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

class RadialLauncher extends StatefulWidget {
  const RadialLauncher({super.key});

  @override
  State<RadialLauncher> createState() => _State();
}

class _State extends State<RadialLauncher> with TickerProviderStateMixin {
  bool _open = false;
  int? _selSlot;
  int _offset = 0;
  final Stopwatch _pageStopwatch = Stopwatch()..start();

  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
  );
  late final Animation<double> _anim = CurvedAnimation(
    parent: _ctrl,
    curve: Curves.easeOutCubic,
  );

  Route<void> _chatRoute() {
    return PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 420),
      reverseTransitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (_, _, _) => const AgentChatScreen(),
      transitionsBuilder: (_, animation, _, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );

        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  void _openChat() {
    HapticFeedback.mediumImpact();
    if (_open) {
      setState(() {
        _open = false;
        _selSlot = null;
      });
      _ctrl.reverse();
    }
    Navigator.of(context).push(_chatRoute());
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
    if (vx.abs() < 650) return;
    _nudge(vx > 0 ? 1 : -1, clearSelection: true);
  }

  void _nudge(int d, {bool clearSelection = false}) {
    final total = _kApps.length;
    if (total == 0) return;
    setState(() {
      _offset = (_offset + d) % total;
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

    final total = _kApps.length;
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

  Offset _computeAnchor(BoxConstraints c) {
    return Offset(
      math.max(
        _kOuterR + _kCornerInset,
        c.maxWidth - _kArcRightReach - _kCornerInset,
      ),
      c.maxHeight - _kHubR - _kCornerInset,
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (_, c) {
        final anchor = _computeAnchor(c);
        return GestureDetector(
          onDoubleTap: _toggle,
          onPanStart: (d) => _panStart(d, anchor),
          onPanUpdate: (d) => _pan(d, anchor),
          onPanEnd: _panEnd,
          onTapDown: (d) => _tap(d, anchor),
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
                        apps: _kApps,
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
                  onLongPress: _openChat,
                  child: const _Hub(key: ValueKey('launcher-hub')),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

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
          color: Colors.black.withOpacity(0.5),
          blurRadius: 20 * _kLauncherScale,
          spreadRadius: 4 * _kLauncherScale,
        ),
      ],
    ),
  );
}

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
    ..color = Colors.black.withOpacity(0.35)
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8 * _kLauncherScale);
  static final Paint _previewFillPaint = Paint()
    ..color = const Color(0xFFD9D9D9);
  static final Paint _bgShadowPaint = Paint()
    ..color = Colors.black.withOpacity(0.4)
    ..maskFilter = const MaskFilter.blur(
      BlurStyle.normal,
      10 * _kLauncherScale,
    );
  static final Paint _bgFillPaint = Paint()..color = const Color(0xFFD9D9D9);
  static final Paint _selectionGlowPaint = Paint()
    ..color = const Color(0xFFFF5C35).withOpacity(0.25)
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8 * _kLauncherScale);
  static final Paint _selectionFillPaint = Paint()
    ..color = const Color(0xFFFF5C35).withOpacity(0.6);
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

  static Offset _pointFor(Offset anchor, double radius, double angle) {
    return Offset(
      anchor.dx + radius * math.cos(angle),
      anchor.dy + radius * math.sin(angle),
    );
  }

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
    final startOuterArc = _pointFor(
      anchor,
      _kOuterR,
      _kArcStartRad + outerDelta,
    );
    final startOuter = _pointFor(anchor, _kOuterR, _kArcStartRad);
    final startInner = _pointFor(anchor, _kInnerR, _kArcStartRad);
    final endOuter = _pointFor(anchor, _kOuterR, _kArcEndRad);
    final endInner = _pointFor(anchor, _kInnerR, _kArcEndRad);
    final endOuterCorner = _pointFor(anchor, _kOuterR - cornerR, _kArcEndRad);
    final endInnerCorner = _pointFor(anchor, _kInnerR + cornerR, _kArcEndRad);
    final endInnerArc = _pointFor(anchor, _kInnerR, _kArcEndRad - innerDelta);
    final startInnerCorner = _pointFor(
      anchor,
      _kInnerR + cornerR,
      _kArcStartRad,
    );
    final startOuterCorner = _pointFor(
      anchor,
      _kOuterR - cornerR,
      _kArcStartRad,
    );

    path.moveTo(startOuterArc.dx, startOuterArc.dy);
    path.arcTo(
      outerRect,
      _kArcStartRad + outerDelta,
      _kArcSpanRad - 2 * outerDelta,
      false,
    );
    path.quadraticBezierTo(
      endOuter.dx,
      endOuter.dy,
      endOuterCorner.dx,
      endOuterCorner.dy,
    );
    path.lineTo(endInnerCorner.dx, endInnerCorner.dy);
    path.quadraticBezierTo(
      endInner.dx,
      endInner.dy,
      endInnerArc.dx,
      endInnerArc.dy,
    );
    path.arcTo(
      innerRect,
      _kArcEndRad - innerDelta,
      -(_kArcSpanRad - 2 * innerDelta),
      false,
    );
    path.quadraticBezierTo(
      startInner.dx,
      startInner.dy,
      startInnerCorner.dx,
      startInnerCorner.dy,
    );
    path.lineTo(startOuterCorner.dx, startOuterCorner.dy);
    path.quadraticBezierTo(
      startOuter.dx,
      startOuter.dy,
      startOuterArc.dx,
      startOuterArc.dy,
    );
    path.close();
    return path;
  }

  Offset _point(double radius, double angle) {
    return _pointFor(anchor, radius, angle);
  }

  Offset _tangentPoint(double radius, double tangentOffset, double angle) {
    return Offset(
      anchor.dx +
          radius * math.cos(angle) +
          tangentOffset * math.cos(angle + math.pi / 2),
      anchor.dy +
          radius * math.sin(angle) +
          tangentOffset * math.sin(angle + math.pi / 2),
    );
  }

  double _towardTopLean(double angle) {
    const top = math.pi * 1.5;
    var delta = top - angle;
    while (delta > math.pi) {
      delta -= math.pi * 2;
    }
    while (delta < -math.pi) {
      delta += math.pi * 2;
    }
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

  TextPainter _createPreviewPainter(AppEntry app) {
    return TextPainter(
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
  }

  Path _buildSelectionPath(int slot) {
    final segS = _kMenuStartRad + slot * _segRad;
    final wedge = Path()
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
    return wedge;
  }

  void _drawDivider(Canvas canvas, double rad) {
    final start = _point(_kInnerR + 8 * _kLauncherScale, rad);
    final end = _point(_kOuterR - 14 * _kLauncherScale, rad);
    canvas.drawLine(start, end, _dividerPaint);
  }

  void _drawPreview(
    Canvas canvas,
    _LabelLayout selectedLabel,
    TextPainter previewPainter,
  ) {
    final previewRad =
        selectedLabel.midRad + _towardTopLean(selectedLabel.midRad);

    canvas.save();
    canvas.translate(anchor.dx, anchor.dy);
    canvas.rotate(previewRad);
    canvas.drawPath(_previewTabPath, _previewShadowPaint);
    canvas.drawPath(_previewTabPath, _previewFillPaint);
    canvas.restore();

    final textCenter = _tangentPoint(
      _kOuterR + 40 * _kLauncherScale,
      2 * _kLauncherScale,
      previewRad,
    );

    canvas.save();
    canvas.translate(textCenter.dx, textCenter.dy);
    canvas.rotate(previewRad + math.pi);
    previewPainter.paint(
      canvas,
      Offset(-previewPainter.width / 2, -previewPainter.height / 2),
    );
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
