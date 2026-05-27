import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:wrangl_native/wrangl_native.dart';

import '../agent/gemma_client.dart';
import '../agent/harness/harness.dart';
import '../agent/model_config.dart';

// ─── Window sizing ───────────────────────────────────────────────────────────
const double kBubbleWindow = 80;

/// Workaround for flutter_overlay_window 0.5.0's broken `resizeOverlay` height
/// handling: `WindowSize.matchParent` (-1) is passed through `dpToPx` and
/// becomes ~-3 px.  We always resolve the fullscreen size explicitly.
Size _fullscreenDp() {
  final view = WidgetsBinding.instance.platformDispatcher.views.first;
  return view.physicalSize / view.devicePixelRatio;
}

// ─── Palette ─────────────────────────────────────────────────────────────────
const _kRed = Color(0xFFFF2200);
const _kWhite = Color(0xFFF0EFEB);
const _kSolidBg = Color(0xFF1A1A1A);
final _kBubbleBlack = Colors.black.withValues(alpha: 0.80);
final _kComposer = Colors.black.withValues(alpha: 0.80);

enum _OverlayMode { collapsed, selecting, expanded }

// ─── Overlay-side chat message ────────────────────────────────────────────────
class _Msg {
  final bool fromUser;
  final String text;
  _Msg(this.fromUser, this.text);
}

// ─── Overlay-side agent (own model in this isolate) ───────────────────────────
class _OverlayAgent extends ChangeNotifier {
  GemmaModelClient? _client;
  WranglHarness? _harness;

  Uint8List? pendingImage;

  bool loading = false;
  bool booting = false;
  bool ready = false;
  String? error;
  final List<_Msg> messages = [];

  Future<void> ensureLoaded() async {
    if (ready || booting) return;
    booting = true;
    error = null;
    notifyListeners();
    try {
      final path = await ModelConfig.path();
      _client = GemmaModelClient(path);
      await _client!.loadModel(withVision: true);
      _harness = WranglHarness.load(_complete);
      ready = true;
    } catch (e) {
      error = '$e';
    } finally {
      booting = false;
      notifyListeners();
    }
  }

  Future<String> _complete({
    required String system,
    required List<Map<String, dynamic>> history,
    Uint8List? image,
    int maxTokens = 512,
  }) {
    return _client!.complete(
      system,
      history,
      maxTokens: maxTokens,
      image: image,
    );
  }

  Future<void> send(String text, {Uint8List? image}) async {
    if (!ready || _harness == null || loading) return;

    final prior = messages
        .map(
          (m) => <String, dynamic>{
            'role': m.fromUser ? 'user' : 'assistant',
            'content': m.text,
          },
        )
        .toList();
    if (prior.length > 6) prior.removeRange(0, prior.length - 6);

    messages.add(_Msg(true, text));
    loading = true;
    notifyListeners();

    try {
      final reply = await _harness!.handle(
        text,
        image: image,
        priorTurns: prior,
      );
      messages.add(_Msg(false, reply));
    } catch (e) {
      messages.add(_Msg(false, 'Error: $e'));
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _client?.dispose();
    super.dispose();
  }
}

// ─── Root widget for the overlay isolate ──────────────────────────────────────
class WranglBubbleRoot extends StatelessWidget {
  const WranglBubbleRoot({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      color: Color(0x00000000),
      home: _BubbleSurface(),
    );
  }
}

class _BubbleSurface extends StatefulWidget {
  const _BubbleSurface();

  @override
  State<_BubbleSurface> createState() => _BubbleSurfaceState();
}

class _BubbleSurfaceState extends State<_BubbleSurface> {
  final _agent = _OverlayAgent();
  final _input = TextEditingController();
  final _scroll = ScrollController();
  StreamSubscription<Map<String, dynamic>>? _assistSub;
  _OverlayMode _mode = _OverlayMode.collapsed;
  bool _busy = false;
  bool _autoExpandChecked = false;

  Uint8List? _screenshot;
  List<Offset> _lassoPoints = [];
  Rect? _cropRect;

  @override
  void initState() {
    super.initState();
    _agent.addListener(_onAgent);
    _assistSub = WranglNative.assistStream.listen(_onAssist);
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkAutoExpand());
  }

  void _checkAutoExpand() {
    if (_autoExpandChecked || _mode != _OverlayMode.collapsed || !mounted) {
      return;
    }
    _autoExpandChecked = true;
    if (MediaQuery.of(context).size.width > kBubbleWindow + 50) {
      _expand(haptic: false);
    }
  }

  @override
  void dispose() {
    _agent.removeListener(_onAgent);
    _agent.dispose();
    _input.dispose();
    _scroll.dispose();
    _assistSub?.cancel();
    super.dispose();
  }

  void _onAssist(Map<String, dynamic> payload) {
    final image = payload['image'] as Uint8List?;
    final hint = payload['hint'] as String?;
    if (image != null) {
      _screenshot = image;
    }
    if (hint != null && hint.isNotEmpty) {
      _input.text = hint;
    }
    _enterSelection();
  }

  void _onAgent() {
    if (!mounted) return;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  void _scrollToBottom() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(
      _scroll.position.maxScrollExtent,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
  }

  // ── expand / collapse ──────────────────────────────────────────────────────

  Future<void> _expand({bool haptic = true}) async {
    if (_busy || _mode == _OverlayMode.expanded) return;
    _busy = true;
    if (haptic) HapticFeedback.mediumImpact();
    final fs = _fullscreenDp();
    await FlutterOverlayWindow.resizeOverlay(
      fs.width.round(),
      fs.height.round(),
      false,
    );
    await FlutterOverlayWindow.updateFlag(OverlayFlag.focusPointer);
    if (mounted) setState(() => _mode = _OverlayMode.expanded);
    _busy = false;
    _agent.ensureLoaded();
  }

  Future<void> _collapse() async {
    if (_busy || _mode == _OverlayMode.collapsed) return;
    _busy = true;
    FocusScope.of(context).unfocus();
    setState(() {
      _mode = _OverlayMode.collapsed;
      _screenshot = null;
      _lassoPoints = [];
      _cropRect = null;
    });
    await FlutterOverlayWindow.updateFlag(OverlayFlag.defaultFlag);
    await FlutterOverlayWindow.resizeOverlay(
      kBubbleWindow.toInt(),
      kBubbleWindow.toInt(),
      true,
    );
    _busy = false;
  }

  // ── selection overlay ──────────────────────────────────────────────────────

  Future<void> _enterSelection() async {
    if (_busy || _mode == _OverlayMode.selecting) return;
    _busy = true;
    final fs = _fullscreenDp();
    await FlutterOverlayWindow.resizeOverlay(
      fs.width.round(),
      fs.height.round(),
      false,
    );
    await FlutterOverlayWindow.updateFlag(OverlayFlag.defaultFlag);
    if (mounted) {
      setState(() {
        _mode = _OverlayMode.selecting;
        _lassoPoints = [];
        _cropRect = null;
      });
    }
    _busy = false;
  }

  void _onLassoStart(DragStartDetails d) {
    _lassoPoints = [d.localPosition];
    _cropRect = null;
    setState(() {});
  }

  void _onLassoUpdate(DragUpdateDetails d) {
    _lassoPoints.add(d.localPosition);
    setState(() {});
  }

  void _onLassoEnd(DragEndDetails d) {
    if (_lassoPoints.length < 3) {
      _collapse();
      return;
    }
    _cropRect = _computeBoundingBox(_lassoPoints);
    _cropAndSend();
  }

  Rect _computeBoundingBox(List<Offset> points) {
    if (points.isEmpty) return Rect.zero;
    double minX = double.infinity, minY = double.infinity;
    double maxX = 0, maxY = 0;
    for (final p in points) {
      minX = math.min(minX, p.dx);
      minY = math.min(minY, p.dy);
      maxX = math.max(maxX, p.dx);
      maxY = math.max(maxY, p.dy);
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  Future<void> _cropAndSend() async {
    if (_screenshot == null || _cropRect == null) return;

    final viewSize = MediaQuery.sizeOf(context);
    final completer = Completer<ui.Image>();
    ui.decodeImageFromList(
      Uint8List.fromList(_screenshot!),
      completer.complete,
    );
    final image = await completer.future;

    final scaleX = image.width / viewSize.width;
    final scaleY = image.height / viewSize.height;

    final src = Rect.fromLTWH(
      _cropRect!.left * scaleX,
      _cropRect!.top * scaleY,
      _cropRect!.width * scaleX,
      _cropRect!.height * scaleY,
    );

    final destSize = Size(src.width, src.height);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, src);
    canvas.drawImageRect(image, src, Offset.zero & destSize, Paint());
    final picture = recorder.endRecording();
    final cropped = await picture.toImage(
      destSize.width.toInt(),
      destSize.height.toInt(),
    );
    final bytes = await cropped.toByteData(format: ui.ImageByteFormat.png);

    if (bytes != null) {
      _agent.pendingImage = bytes.buffer.asUint8List();
    }

    await FlutterOverlayWindow.updateFlag(OverlayFlag.focusPointer);
    if (mounted) {
      setState(() => _mode = _OverlayMode.expanded);
    }
    _agent.ensureLoaded();
    if (_input.text.isNotEmpty) {
      _send();
    }
  }

  void _send() {
    var text = _input.text.trim();
    if (text.isEmpty) return;
    _input.clear();

    if (text.startsWith('/exp')) {
      text = text.substring(4).trim();
      if (text.isEmpty) text = 'Describe what is on my screen';
      _captureAndSend(text);
      return;
    }

    _agent.send(text, image: _agent.pendingImage);
    _agent.pendingImage = null;
  }

  Future<void> _captureAndSend(String prompt) async {
    try {
      final image = await WranglNative.captureScreen();
      _agent.send(prompt, image: image);
    } catch (e) {
      _agent.send('/exp failed: $e');
    }
  }

  // ── build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!_autoExpandChecked) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkAutoExpand());
    }
    return Material(
      type: MaterialType.transparency,
      child: switch (_mode) {
        _OverlayMode.collapsed => _buildBubble(),
        _OverlayMode.selecting => _buildSelector(context),
        _OverlayMode.expanded => _buildChat(context),
      },
    );
  }

  Widget _buildBubble() {
    return GestureDetector(
      onTap: _expand,
      onLongPress: _expand,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: kBubbleWindow,
        height: kBubbleWindow,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _kBubbleBlack,
          border: Border.all(color: _kWhite, width: 2.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 12,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Center(
          child: Text(
            'W',
            style: TextStyle(
              color: _kWhite,
              fontSize: 28,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSelector(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Stack(
      children: [
        if (_screenshot != null)
          Positioned.fill(
            child: RepaintBoundary(
              child: Image.memory(
                _screenshot!,
                fit: BoxFit.fill,
                width: size.width,
                height: size.height,
              ),
            ),
          ),
        Positioned.fill(
          child: GestureDetector(
            onPanStart: _onLassoStart,
            onPanUpdate: _onLassoUpdate,
            onPanEnd: _onLassoEnd,
            child: CustomPaint(
              painter: _LassoPainter(
                points: _lassoPoints,
                selectionRect: _cropRect,
                size: size,
              ),
              size: size,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildChat(BuildContext context) {
    final media = MediaQuery.of(context);
    final insets = media.viewInsets;
    final pad = media.padding;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _collapse();
      },
      child: Container(
        color: Colors.black.withValues(alpha: 0.56),
        child: AnimatedPadding(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: EdgeInsets.fromLTRB(
            16,
            pad.top + 16,
            16,
            pad.bottom + insets.bottom + 16,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final panelWidth = math.min(constraints.maxWidth, 340.0);
              final panelHeight = math.min(constraints.maxHeight, 520.0);
              return Align(
                alignment: insets.bottom > 0
                    ? Alignment.topCenter
                    : Alignment.center,
                child: SizedBox(
                  width: panelWidth,
                  height: panelHeight,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: _kSolidBg,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.45),
                          blurRadius: 22,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Column(
                        children: [
                          _buildChatHeader(),
                          Expanded(
                            child:
                                _agent.error != null && _agent.messages.isEmpty
                                ? _StatusCard(
                                    label: _agent.error!,
                                    isError: true,
                                  )
                                : _agent.booting && _agent.messages.isEmpty
                                ? const _StatusCard(label: 'STARTING AGENT...')
                                : ListView.separated(
                                    controller: _scroll,
                                    padding: const EdgeInsets.fromLTRB(
                                      16,
                                      8,
                                      16,
                                      8,
                                    ),
                                    itemCount: _agent.messages.length,
                                    separatorBuilder: (_, _) =>
                                        const SizedBox(height: 10),
                                    itemBuilder: (_, i) =>
                                        _Bubble(_agent.messages[i]),
                                  ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                            child: _Composer(
                              controller: _input,
                              onSend: _send,
                              enabled: _agent.ready && !_agent.loading,
                              isLoading: _agent.loading,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildChatHeader() {
    return Row(
      children: [
        GestureDetector(
          onTap: _collapse,
          child: Container(
            margin: const EdgeInsets.all(4),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _kBubbleBlack,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.keyboard_arrow_down,
              color: _kWhite,
              size: 22,
            ),
          ),
        ),
        const Spacer(),
      ],
    );
  }
}

// ─── Lasso painter ────────────────────────────────────────────────────────────
class _LassoPainter extends CustomPainter {
  final List<Offset> points;
  final Rect? selectionRect;
  final Size size;

  _LassoPainter({
    required this.points,
    required this.selectionRect,
    required this.size,
  });

  @override
  void paint(Canvas canvas, Size _) {
    final overlayPaint = Paint()..color = Colors.black.withValues(alpha: 0.35);

    if (selectionRect != null) {
      final outer = Path()..addRect(Offset.zero & size);
      final inner = Path()..addRect(selectionRect!);
      final clipped = Path.combine(PathOperation.difference, outer, inner);
      canvas.drawPath(clipped, overlayPaint);
    } else if (points.length > 1) {
      canvas.drawRect(Offset.zero & size, overlayPaint);
    }

    if (points.length > 1) {
      final path = Path()..addPolygon(points, false);
      final stroke = Paint()
        ..color = Colors.white
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      canvas.drawPath(path, stroke);
    }
  }

  @override
  bool shouldRepaint(covariant _LassoPainter old) =>
      old.points != points || old.selectionRect != selectionRect;
}

// ─── Chat bubble ──────────────────────────────────────────────────────────────
class _Bubble extends StatelessWidget {
  final _Msg msg;
  const _Bubble(this.msg);

  @override
  Widget build(BuildContext context) {
    final maxW = MediaQuery.of(context).size.width * 0.76;
    return Align(
      alignment: msg.fromUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxW),
        child: Container(
          decoration: BoxDecoration(
            color: _kBubbleBlack,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(msg.fromUser ? 18 : 4),
              bottomRight: Radius.circular(msg.fromUser ? 4 : 18),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(14, 11, 14, 12),
          child: Text(
            msg.text,
            style: TextStyle(
              color: _kWhite,
              fontSize: 14,
              fontWeight: msg.fromUser ? FontWeight.w700 : FontWeight.w500,
              height: 1.3,
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Composer ─────────────────────────────────────────────────────────────────
class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  final bool enabled;
  final bool isLoading;

  const _Composer({
    required this.controller,
    required this.onSend,
    required this.enabled,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _kComposer,
        borderRadius: BorderRadius.circular(28),
      ),
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              enabled: enabled,
              onSubmitted: enabled ? (_) => onSend() : null,
              cursorColor: _kRed,
              style: const TextStyle(
                color: _kWhite,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
              decoration: InputDecoration(
                hintText: enabled ? 'Message…' : 'Loading…',
                hintStyle: TextStyle(
                  color: _kWhite.withValues(alpha: 0.4),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                border: InputBorder.none,
              ),
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: enabled ? onSend : null,
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: enabled ? _kWhite : _kWhite.withValues(alpha: 0.3),
              ),
              child: isLoading
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.black,
                      ),
                    )
                  : const Icon(
                      Icons.arrow_upward,
                      color: Colors.black,
                      size: 20,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Status card (loading / error) ────────────────────────────────────────────
class _StatusCard extends StatelessWidget {
  final String label;
  final bool isError;
  const _StatusCard({required this.label, this.isError = false});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 32),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: _kBubbleBlack,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isError)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: _kRed),
              ),
            if (!isError) const SizedBox(height: 14),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isError ? _kRed : _kWhite,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
