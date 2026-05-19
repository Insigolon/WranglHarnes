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
        body: SafeArea(child: Center(child: RadialLauncher())),
      ),
    );
  }
}

// ─── Data ────────────────────────────────────────────────

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

// ─── Constants ───────────────────────────────────────────

// The arc sweeps from _kArcStart to _kArcEnd (degrees, standard math angles)
const double _kArcStart = 205.0;
const double _kArcEnd = 335.0;

const double _kHubR = 46.0;

// Crescent band radii
const double _kInnerR = 72.0; // inner edge of band
const double _kOuterR = 148.0; // outer edge of band

// Corner radius on the two arc-tip caps (r=13 from Figma)
const double _kCapR = 13.0;

double _deg(double r) => r * 180 / math.pi;
double _rad(double d) => d * math.pi / 180;

// ─── Widget ──────────────────────────────────────────────

class RadialLauncher extends StatefulWidget {
  const RadialLauncher({super.key});
  @override
  State<RadialLauncher> createState() => _State();
}

class _State extends State<RadialLauncher> with TickerProviderStateMixin {
  bool _open = false;
  String? _sel;
  int _offset = 0;
  double _dragAccum = 0;
  int _lastMs = 0;

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

  void _pan(DragUpdateDetails d) {
    if (!_open) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastMs < 16) return;
    _lastMs = now;
    _dragAccum += d.delta.dx;
    final s = (_dragAccum / 30).truncate();
    if (s != 0) {
      setState(() {
        _offset += s;
        _dragAccum -= s * 30;
      });
    }
  }

  void _panEnd(DragEndDetails d) {
    final s = (d.velocity.pixelsPerSecond.dx / 480).round();
    if (s != 0) setState(() => _offset += s);
  }

  void _nudge(int d) => setState(() => _offset += d);

  void _tap(TapDownDetails d, Offset anchor) {
    if (!_open) return;
    final dx = d.localPosition.dx - anchor.dx;
    final dy = d.localPosition.dy - anchor.dy;
    final dist = math.sqrt(dx * dx + dy * dy);
    final ang = (math.atan2(dy, dx) * 180 / math.pi + 360) % 360;
    if (dist < _kInnerR ||
        dist > _kOuterR ||
        ang < _kArcStart - 2 ||
        ang > _kArcEnd + 2) {
      setState(() => _sel = null);
      return;
    }
    final n = _kApps.length;
    final i = (((ang - _kArcStart) / (_kArcEnd - _kArcStart)) * n)
        .floor()
        .clamp(0, n - 1);
    final idx = ((i + _offset) % n + n) % n;
    setState(() => _sel = _kApps[idx].id);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (_, c) {
        final anchor = Offset(c.maxWidth / 2, c.maxHeight - 24);
        return AnimatedBuilder(
          animation: _anim,
          builder: (_, __) => GestureDetector(
            onDoubleTap: _toggle,
            onPanUpdate: _pan,
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
                if (_anim.value > 0.5) ...[
                  _arrow(anchor, left: true),
                  _arrow(anchor, left: false),
                ],
                Positioned(
                  left: anchor.dx - _kHubR,
                  top: anchor.dy - _kHubR,
                  child: GestureDetector(
                    onDoubleTap: _toggle,
                    child: _Hub(t: _anim.value),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _arrow(Offset anchor, {required bool left}) {
    final deg = left ? _kArcStart - 16.0 : _kArcEnd + 16.0;
    final r = _rad(deg);
    final mid = (_kInnerR + _kOuterR) / 2;
    return Positioned(
      left: anchor.dx + mid * math.cos(r) - 14,
      top: anchor.dy + mid * math.sin(r) - 14,
      child: GestureDetector(
        onTap: () => _nudge(left ? -1 : 1),
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.13),
            shape: BoxShape.circle,
          ),
          child: Icon(
            left ? Icons.chevron_left : Icons.chevron_right,
            color: Colors.white.withOpacity(0.85),
            size: 18,
          ),
        ),
      ),
    );
  }
}

// ─── Hub ─────────────────────────────────────────────────

class _Hub extends StatelessWidget {
  final double t;
  const _Hub({required this.t});
  @override
  Widget build(BuildContext context) => Container(
    width: _kHubR * 2,
    height: _kHubR * 2,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: const Color(0xFF1C1C1E),
      border: Border.all(
        color: Colors.white.withOpacity(0.08 + 0.06 * t),
        width: 1.5,
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.5),
          blurRadius: 20,
          spreadRadius: 4,
        ),
      ],
    ),
    child: Icon(
      Icons.apps_rounded,
      color: Colors.white.withOpacity(0.85),
      size: 26,
    ),
  );
}

// ─── Painter ─────────────────────────────────────────────

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

  // Build the full crescent path:
  //  - outer arc from startDeg → endDeg at _kOuterR
  //  - rounded cap at end tip  (r = _kCapR)
  //  - inner arc from endDeg → startDeg at _kInnerR  (reversed)
  //  - rounded cap at start tip
  Path _crescentPath(double startDeg, double endDeg) {
    final s = _rad(startDeg);
    final e = _rad(endDeg);
    final sweep = e - s; // positive
    final path = Path();

    final outerRect = Rect.fromCircle(center: anchor, radius: _kOuterR);
    final innerRect = Rect.fromCircle(center: anchor, radius: _kInnerR);

    // ── outer arc: s → e ────────────────────────────────
    path.addArc(outerRect, s, sweep);

    // ── end cap (at angle e) ─────────────────────────────
    // The cap connects outerR at angle e to innerR at angle e.
    // It's a rounded rectangle whose long axis is radial at angle e.
    // We approximate this with a bezier round-corner:
    //   straight line from outer edge inward, with rounded corners.
    final oeX = anchor.dx + _kOuterR * math.cos(e);
    final oeY = anchor.dy + _kOuterR * math.sin(e);
    final ieX = anchor.dx + _kInnerR * math.cos(e);
    final ieY = anchor.dy + _kInnerR * math.sin(e);

    // direction vectors
    final radDX = math.cos(e); // points outward from anchor
    final radDY = math.sin(e);
    // tangent (perpendicular, clockwise)
    final tanDX = radDY;
    final tanDY = -radDX;

    // Corner radius clamped to half band width
    final cr = math.min(_kCapR, (_kOuterR - _kInnerR) / 2);

    // We draw: from outer-edge point, curve inward
    // Using quadratic bezier for the rounded corner feel
    // Control point offset along tangent = cr
    path.lineTo(oeX + tanDX * cr, oeY + tanDY * cr);
    path.quadraticBezierTo(oeX, oeY, ieX + tanDX * cr, ieY + tanDY * cr);

    // Straight line to where inner arc starts at angle e
    path.lineTo(ieX, ieY);

    // ── inner arc: e → s (reversed) ─────────────────────
    path.addArc(innerRect, e, -sweep);

    // ── start cap (at angle s) ───────────────────────────
    final osX = anchor.dx + _kOuterR * math.cos(s);
    final osY = anchor.dy + _kOuterR * math.sin(s);
    final isX = anchor.dx + _kInnerR * math.cos(s);
    final isY = anchor.dy + _kInnerR * math.sin(s);

    // tangent at s, counter-clockwise (opposite direction for start cap)
    final tanSDX = -math.sin(s);
    final tanSDY = math.cos(s);

    path.lineTo(isX - tanSDX * cr, isY - tanSDY * cr);
    path.quadraticBezierTo(isX, isY, osX - tanSDX * cr, osY - tanSDY * cr);
    path.lineTo(osX, osY);

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

    final n = apps.length;
    final spanDeg = _kArcEnd - _kArcStart;
    final segDeg = spanDeg / n;

    // ── 1. Draw full crescent background ────────────────
    final bgPath = _crescentPath(_kArcStart, _kArcEnd);

    // soft drop shadow
    canvas.drawPath(
      bgPath,
      Paint()
        ..color = Colors.black.withOpacity(0.4)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
    // fill
    canvas.drawPath(bgPath, Paint()..color = const Color(0xFFD9D9D9));

    // ── 2. Clip to crescent so nothing bleeds outside ───
    canvas.save();
    canvas.clipPath(bgPath);

    // ── 3. Selected segment highlight ───────────────────
    if (sel != null) {
      for (int i = 0; i < n; i++) {
        final idx = ((i + offset) % n + n) % n;
        if (apps[idx].id != sel) continue;
        final segS = _rad(_kArcStart + i * segDeg);
        final segE = _rad(_kArcStart + (i + 1) * segDeg);
        final segSweep = segE - segS;

        // build a wedge path for just this segment
        final wedge = Path();
        wedge.moveTo(anchor.dx, anchor.dy);
        wedge.addArc(
          Rect.fromCircle(center: anchor, radius: _kOuterR + 10),
          segS,
          segSweep,
        );
        wedge.lineTo(anchor.dx, anchor.dy);

        // glow
        canvas.drawPath(
          wedge,
          Paint()
            ..color = const Color(0xFFFF5C35).withOpacity(0.25)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
        );
        // solid tint
        canvas.drawPath(
          wedge,
          Paint()..color = const Color(0xFFFF5C35).withOpacity(0.6),
        );
        break;
      }
    }

    // ── 4. Radial divider lines (thin, dark) ────────────
    canvas.restore(); // end clip

    // ── 5. Labels ────────────────────────────────────────
    // Each label is drawn at the angular midpoint of its segment,
    // at radial midpoint of the band, rotated so text is upright
    // along the spoke (reading from outer edge toward hub).
    for (int i = 0; i < n; i++) {
      final idx = ((i + offset) % n + n) % n;
      final app = apps[idx];
      final isSel = sel == app.id;

      final midDeg = _kArcStart + (i + 0.5) * segDeg;
      final midRad = _rad(midDeg);
      final midR = (_kInnerR + _kOuterR) / 2;

      final tx = anchor.dx + midR * math.cos(midRad);
      final ty = anchor.dy + midR * math.sin(midRad);

      final tp = TextPainter(
        text: TextSpan(
          text: app.label,
          style: TextStyle(
            fontSize: isSel ? 10.5 : 9.5,
            fontWeight: FontWeight.w700,
            color: isSel ? Colors.white : const Color(0xFF1A1A1A),
            letterSpacing: 0.1,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 72);

      canvas.save();
      canvas.translate(tx, ty);

      // Rotate so text stands radially, reading inward.
      // midRad points outward. We want text upright along this spoke,
      // with the top toward the outer edge → rotate by midRad − π/2,
      // then flip 180° so it reads inward (top = outside).
      canvas.rotate(midRad + math.pi / 2);

      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      canvas.restore();
    }

    canvas.restore(); // end saveLayer
  }

  @override
  bool shouldRepaint(covariant _Painter old) =>
      old.t != t || old.sel != sel || old.offset != offset;
}
