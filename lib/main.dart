import 'dart:math' as math;
import 'package:flutter/material.dart';

void main() => runApp(const _App());

class _App extends StatelessWidget {
  const _App();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Color(0xFF0D0D0D),
        body: SafeArea(child: RadialLauncher()),
      ),
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

double _rad(double d) => d * math.pi / 180;

class RadialLauncher extends StatefulWidget {
  const RadialLauncher({super.key});

  @override
  State<RadialLauncher> createState() => _State();
}

class _State extends State<RadialLauncher> with TickerProviderStateMixin {
  bool _open = false;
  String? _sel;
  int _offset = 0;
  int _lastNudgeMs = 0;

  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
  );
  late final Animation<double> _anim = CurvedAnimation(
    parent: _ctrl,
    curve: Curves.easeOutCubic,
  );

  void _toggle() {
    setState(() => _open = !_open);
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

  void _panEnd(DragEndDetails d) {}

  void _nudge(int d) => setState(() => _offset += d);

  void _pageByDrag(int d) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastNudgeMs < 220) return;
    _lastNudgeMs = now;
    _nudge(d);
  }

  void _updateHover(
    Offset localPosition,
    Offset anchor, {
    bool allowPaging = true,
  }) {
    final dx = localPosition.dx - anchor.dx;
    final dy = localPosition.dy - anchor.dy;
    final dist = math.sqrt(dx * dx + dy * dy);
    final ang = (math.atan2(dy, dx) * 180 / math.pi + 360) % 360;
    if (dist < _kInnerR ||
        dist > _kOuterR ||
        ang < _kArcStart - 2 ||
        ang > _kArcEnd + 2) {
      setState(() => _sel = null);
      return;
    }

    if (ang < _kMenuStart) {
      allowPaging ? _pageByDrag(-1) : _nudge(-1);
      return;
    }
    if (ang > _kMenuEnd) {
      allowPaging ? _pageByDrag(1) : _nudge(1);
      return;
    }

    final total = _kApps.length;
    final visible = math.min(_kVisibleAppCount, total);
    final i = (((ang - _kMenuStart) / (_kMenuEnd - _kMenuStart)) * visible)
        .floor()
        .clamp(0, visible - 1);
    final idx = ((i + _offset) % total + total) % total;
    setState(() => _sel = _kApps[idx].id);
  }

  void _tap(TapDownDetails d, Offset anchor) {
    if (!_open) return;
    _updateHover(d.localPosition, anchor, allowPaging: false);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (_, c) {
        final arcRightReach = _kOuterR * math.cos(_rad(360 - _kArcEnd));
        final anchor = Offset(
          math.max(
            _kOuterR + _kCornerInset,
            c.maxWidth - arcRightReach - _kCornerInset,
          ),
          c.maxHeight - _kHubR - _kCornerInset,
        );
        return AnimatedBuilder(
          animation: _anim,
          builder: (_, _) => GestureDetector(
            onDoubleTap: _toggle,
            onPanStart: (d) => _panStart(d, anchor),
            onPanUpdate: (d) => _pan(d, anchor),
            onPanEnd: _panEnd,
            onTapDown: (d) => _tap(d, anchor),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                if (_anim.value > 0)
                  RepaintBoundary(
                    child: CustomPaint(
                      size: Size.infinite,
                      painter: _Painter(
                        anchor: anchor,
                        t: _anim.value,
                        apps: _kApps,
                        offset: _offset,
                        sel: _sel,
                      ),
                    ),
                  ),
                Positioned(
                  left: anchor.dx - _kHubR,
                  top: anchor.dy - _kHubR,
                  child: GestureDetector(
                    onDoubleTap: _toggle,
                    child: const _Hub(),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Hub extends StatelessWidget {
  const _Hub();

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

class _Painter extends CustomPainter {
  final Offset anchor;
  final double t;
  final List<AppEntry> apps;
  final int offset;
  final String? sel;

  const _Painter({
    required this.anchor,
    required this.t,
    required this.apps,
    required this.offset,
    required this.sel,
  });

  Offset _point(double radius, double angle) {
    return Offset(
      anchor.dx + radius * math.cos(angle),
      anchor.dy + radius * math.sin(angle),
    );
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

  void _drawDivider(Canvas canvas, double deg) {
    final r = _rad(deg);
    final start = Offset(
      anchor.dx + (_kInnerR + 8 * _kLauncherScale) * math.cos(r),
      anchor.dy + (_kInnerR + 8 * _kLauncherScale) * math.sin(r),
    );
    final end = Offset(
      anchor.dx + (_kOuterR - 14 * _kLauncherScale) * math.cos(r),
      anchor.dy + (_kOuterR - 14 * _kLauncherScale) * math.sin(r),
    );

    canvas.drawLine(
      start,
      end,
      Paint()
        ..color = const Color(0xFF555555)
        ..strokeWidth = 4.5 * _kLauncherScale
        ..strokeCap = StrokeCap.round,
    );
  }

  void _drawPreview(Canvas canvas, AppEntry app, double midRad) {
    final previewRad = midRad + _towardTopLean(midRad);
    final tabStart = _kOuterR - 20 * _kLauncherScale;
    final tabLength = 122 * _kLauncherScale;
    final tabWidth = 52 * _kLauncherScale;
    final tabRadius = 13 * _kLauncherScale;
    final flare = 22 * _kLauncherScale;
    final neckWidth = tabWidth * 0.62;
    final tabEnd = tabStart + tabLength;

    canvas.save();
    canvas.translate(anchor.dx, anchor.dy);
    canvas.rotate(previewRad);

    final tabPath = Path()
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

    canvas.drawPath(
      tabPath,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(
          BlurStyle.normal,
          8 * _kLauncherScale,
        ),
    );
    canvas.drawPath(tabPath, Paint()..color = const Color(0xFFD9D9D9));
    canvas.restore();

    final textCenter = _tangentPoint(
      _kOuterR + 40 * _kLauncherScale,
      2 * _kLauncherScale,
      previewRad,
    );
    final tp = TextPainter(
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

    canvas.save();
    canvas.translate(textCenter.dx, textCenter.dy);
    canvas.rotate(previewRad + math.pi);
    tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
    canvas.restore();
  }

  Path _crescentPath(double startDeg, double endDeg) {
    final s = _rad(startDeg);
    final e = _rad(endDeg);
    final sweep = e - s;
    final cornerR = 14 * _kLauncherScale;
    final outerDelta = cornerR / _kOuterR;
    final innerDelta = cornerR / _kInnerR;
    final path = Path();

    final outerRect = Rect.fromCircle(center: anchor, radius: _kOuterR);
    final innerRect = Rect.fromCircle(center: anchor, radius: _kInnerR);
    final startOuterArc = _point(_kOuterR, s + outerDelta);
    final startOuter = _point(_kOuterR, s);
    final startInner = _point(_kInnerR, s);
    final endOuter = _point(_kOuterR, e);
    final endInner = _point(_kInnerR, e);
    final endOuterCorner = _point(_kOuterR - cornerR, e);
    final endInnerCorner = _point(_kInnerR + cornerR, e);
    final endInnerArc = _point(_kInnerR, e - innerDelta);
    final startInnerCorner = _point(_kInnerR + cornerR, s);
    final startOuterCorner = _point(_kOuterR - cornerR, s);

    path.moveTo(startOuterArc.dx, startOuterArc.dy);
    path.arcTo(outerRect, s + outerDelta, sweep - 2 * outerDelta, false);
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
    path.arcTo(innerRect, e - innerDelta, -(sweep - 2 * innerDelta), false);
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

  @override
  void paint(Canvas canvas, Size size) {
    if (t == 0) return;

    canvas.saveLayer(
      Rect.largest,
      Paint()..color = Color.fromRGBO(255, 255, 255, t),
    );

    final total = apps.length;
    final visible = math.min(_kVisibleAppCount, total);
    if (visible == 0) {
      canvas.restore();
      return;
    }

    final spanDeg = _kMenuEnd - _kMenuStart;
    final segDeg = spanDeg / visible;
    int? selectedSlot;
    AppEntry? selectedApp;

    if (sel != null) {
      for (int i = 0; i < visible; i++) {
        final idx = ((i + offset) % total + total) % total;
        if (apps[idx].id == sel) {
          selectedSlot = i;
          selectedApp = apps[idx];
          break;
        }
      }
    }

    final bgPath = _crescentPath(_kArcStart, _kArcEnd);

    canvas.drawPath(
      bgPath,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.4)
        ..maskFilter = const MaskFilter.blur(
          BlurStyle.normal,
          10 * _kLauncherScale,
        ),
    );
    canvas.drawPath(bgPath, Paint()..color = const Color(0xFFD9D9D9));

    canvas.save();
    canvas.clipPath(bgPath);

    if (selectedSlot != null) {
      final segS = _rad(_kMenuStart + selectedSlot * segDeg);
      final segE = _rad(_kMenuStart + (selectedSlot + 1) * segDeg);
      final segSweep = segE - segS;

      final wedge = Path();
      wedge.moveTo(anchor.dx, anchor.dy);
      wedge.addArc(
        Rect.fromCircle(
          center: anchor,
          radius: _kOuterR + 10 * _kLauncherScale,
        ),
        segS,
        segSweep,
      );
      wedge.lineTo(anchor.dx, anchor.dy);

      canvas.drawPath(
        wedge,
        Paint()
          ..color = const Color(0xFFFF5C35).withValues(alpha: 0.25)
          ..maskFilter = const MaskFilter.blur(
            BlurStyle.normal,
            8 * _kLauncherScale,
          ),
      );
      canvas.drawPath(
        wedge,
        Paint()..color = const Color(0xFFFF5C35).withValues(alpha: 0.6),
      );
    }

    canvas.restore();

    _drawDivider(canvas, _kMenuStart);
    _drawDivider(canvas, _kMenuEnd);

    for (int i = 0; i < visible; i++) {
      final idx = ((i + offset) % total + total) % total;
      final app = apps[idx];
      final isSel = sel == app.id;

      final midDeg = _kMenuStart + (i + 0.5) * segDeg;
      final midRad = _rad(midDeg);
      final midR = (_kInnerR + _kOuterR) / 2;

      final tx = anchor.dx + midR * math.cos(midRad);
      final ty = anchor.dy + midR * math.sin(midRad);

      final tp = TextPainter(
        text: TextSpan(
          text: app.label,
          style: TextStyle(
            fontSize: (isSel ? 10.5 : 9.5) * _kLabelScale,
            fontWeight: FontWeight.w700,
            color: isSel ? Colors.white : const Color(0xFF1A1A1A),
            letterSpacing: 0,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 72 * _kLabelScale);

      canvas.save();
      canvas.translate(tx, ty);
      canvas.rotate(midRad + math.pi);
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      canvas.restore();
    }

    if (selectedSlot != null && selectedApp != null) {
      final midDeg = _kMenuStart + (selectedSlot + 0.5) * segDeg;
      _drawPreview(canvas, selectedApp, _rad(midDeg));
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _Painter old) =>
      old.t != t || old.sel != sel || old.offset != offset;
}
