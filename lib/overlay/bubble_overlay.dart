import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:wrangl_native/wrangl_native.dart';

import '../features/voice/voice_input_service.dart';
import 'overlay_agent.dart';

// ─── Palette ──────────────────────────────────────────────────────────────────
const _kRed = Color(0xFFFF2200);
const _kWhite = Color(0xFFF0EFEB);
const _kBg = Color(0xFF111111);
const _kPill = Color(0xFF1E1E1E);

// ─── Layout ───────────────────────────────────────────────────────────────────
const double _kWindowVPad = 60.0;

enum _OverlayMode { notificationBar, selecting, recording }

// ─── Root ─────────────────────────────────────────────────────────────────────
class WranglBubbleRoot extends StatelessWidget {
  const WranglBubbleRoot({super.key});
  @override
  Widget build(BuildContext context) => const MaterialApp(
    debugShowCheckedModeBanner: false,
    color: Color(0x00000000),
    home: _BubbleSurface(),
  );
}

// ─── Surface ──────────────────────────────────────────────────────────────────
class _BubbleSurface extends StatefulWidget {
  const _BubbleSurface();
  @override
  State<_BubbleSurface> createState() => _BubbleSurfaceState();
}

class _BubbleSurfaceState extends State<_BubbleSurface> {
  final _agent = OverlayAgent();
  final _input = TextEditingController();

  /// Key on the capsule [Material] so [_resizeToContent] can read its
  /// rendered height and resize the native overlay window to match.
  final _colKey = GlobalKey();
  final _scrollCtrl = ScrollController();

  StreamSubscription<Map<String, dynamic>>? _assistSub;
  StreamSubscription? _sharedDataSub;

  _OverlayMode _mode = _OverlayMode.notificationBar;
  bool _busy = false;

  Uint8List? _screenshot;
  List<Offset> _lassoPoints = [];
  Rect? _cropRect;

  final _voiceService = VoiceInputService();
  bool _isRecording = false;

  // ── screen helpers ────────────────────────────────────────────────────────

  Size get _screenDp {
    final v = WidgetsBinding.instance.platformDispatcher.views.first;
    return v.physicalSize / v.devicePixelRatio;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Resize strategy
  //
  // _buildBar wraps its content in an OverflowBox so the capsule measures at
  // its natural (unclipped) height regardless of the current overlay window
  // size.  After the first frame we read the capsule's natural height, resize
  // the native window to fit, then re-measure once more after the layout
  // settles (the second measurement almost always matches the first).
  // ─────────────────────────────────────────────────────────────────────────
  void _resizeToContent() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      int? h = _measure();
      if (h == null) {
        _resizeToContent();
        return;
      }
      await FlutterOverlayWindow.resizeOverlay(360, h, false);
      // Re-measure after the resize takes effect.
      WidgetsBinding.instance.addPostFrameCallback((__) async {
        if (!mounted) return;
        int? h2 = _measure();
        if (h2 != null && h2 != h) {
          await FlutterOverlayWindow.resizeOverlay(360, h2, false);
        }
      });
    });
  }

  /// Reads the capsule's current render height and returns the total overlay
  /// height (content + padding + safety margin) or null if not ready.
  int? _measure() {
    final ctx = _colKey.currentContext;
    if (ctx == null) return null;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    const outerTopPad = 12.0;
    return (box.size.height + outerTopPad + _kWindowVPad).ceil();
  }

  // ── lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _agent.addListener(_onAgent);
    _assistSub = WranglNative.assistStream.listen(_onAssist);
    _sharedDataSub = FlutterOverlayWindow.overlayListener.listen(_onSharedData);
    _agent.ensureLoaded();
    _resizeToContent(); // initial sizing after first frame
  }

  @override
  void dispose() {
    _agent.removeListener(_onAgent);
    _agent.dispose();
    _input.dispose();
    _scrollCtrl.dispose();
    _assistSub?.cancel();
    _sharedDataSub?.cancel();
    _voiceService.dispose();
    super.dispose();
  }

  void _onAgent() {
    if (!mounted) return;
    setState(() {});
    _scrollCtrl.animateTo(0,
        duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    if (_mode == _OverlayMode.notificationBar) _resizeToContent();
  }

  void _onSharedData(dynamic event) {
    if (event is! String) return;
    try {
      final data = jsonDecode(event) as Map<String, dynamic>;
      final vt = data['voiceText'] as String?;
      if (vt != null && vt.isNotEmpty) {
        _input.text = vt;
        _autoSendWhenReady(vt);
      }
      if (data['startVoice'] == true) _startOverlayRecording();
    } catch (_) {}
  }

  void _autoSendWhenReady(String text) {
    if (_agent.ready && !_agent.loading) {
      _send();
      return;
    }
    late final VoidCallback l;
    l = () {
      _agent.removeListener(l);
      if (_agent.ready && !_agent.loading && _input.text == text) _send();
    };
    _agent.addListener(l);
  }

  void _onAssist(Map<String, dynamic> payload) {
    final image = payload['image'] as Uint8List?;
    final hint = payload['hint'] as String?;
    if (image != null) _screenshot = image;
    if (hint != null && hint.isNotEmpty) _input.text = hint;
    _enterSelection();
  }

  // ── selection ─────────────────────────────────────────────────────────────

  Future<void> _enterSelection() async {
    if (_busy || _mode == _OverlayMode.selecting) return;
    _busy = true;
    final fs = _screenDp;
    await FlutterOverlayWindow.resizeOverlay(
      fs.width.round(),
      fs.height.round(),
      false,
    );
    await FlutterOverlayWindow.updateFlag(OverlayFlag.defaultFlag);
    if (mounted)
      setState(() {
        _mode = _OverlayMode.selecting;
        _lassoPoints = [];
        _cropRect = null;
      });
    _busy = false;
  }

  Future<void> _exitSelection() async {
    if (_busy) return;
    _busy = true;
    await FlutterOverlayWindow.updateFlag(OverlayFlag.focusPointer);
    if (mounted)
      setState(() {
        _mode = _OverlayMode.notificationBar;
        _screenshot = null;
        _lassoPoints = [];
        _cropRect = null;
      });
    _resizeToContent();
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

  void _onLassoEnd(DragEndDetails _) {
    if (_lassoPoints.length < 3) {
      _exitSelection();
      return;
    }
    _cropRect = _computeBoundingBox(_lassoPoints);
    _cropAndSend();
  }

  Rect _computeBoundingBox(List<Offset> pts) {
    double minX = double.infinity, minY = double.infinity, maxX = 0, maxY = 0;
    for (final p in pts) {
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
    final dstSz = Size(src.width, src.height);
    final rec = ui.PictureRecorder();
    Canvas(rec, src).drawImageRect(image, src, Offset.zero & dstSz, Paint());
    final pic = rec.endRecording();
    final cropped = await pic.toImage(
      dstSz.width.toInt(),
      dstSz.height.toInt(),
    );
    final bytes = await cropped.toByteData(format: ui.ImageByteFormat.png);
    if (bytes != null) _agent.pendingImage = bytes.buffer.asUint8List();
    await FlutterOverlayWindow.updateFlag(OverlayFlag.focusPointer);
    if (mounted)
      setState(() {
        _mode = _OverlayMode.notificationBar;
        _screenshot = null;
        _lassoPoints = [];
        _cropRect = null;
      });
    _agent.ensureLoaded();
    if (_input.text.isNotEmpty) _send();
    _resizeToContent();
  }

  // ── send ──────────────────────────────────────────────────────────────────

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
      _agent.send(prompt, image: await WranglNative.captureScreen());
    } catch (e) {
      _agent.send('/exp failed: $e');
    }
  }

  Future<void> _pickAndAttachFile() async {
    try {
      final fd = await WranglNative.pickFile();
      if (fd != null)
        setState(() => _agent.pendingImage = fd['bytes'] as Uint8List);
    } catch (_) {}
  }

  // ── voice ─────────────────────────────────────────────────────────────────

  Future<void> _startOverlayRecording() async {
    if (_isRecording) return;
    setState(() => _isRecording = true);
    HapticFeedback.mediumImpact();
    try {
      final fs = _screenDp;
      await FlutterOverlayWindow.resizeOverlay(
        fs.width.round(),
        fs.height.round(),
        false,
      );
      await FlutterOverlayWindow.updateFlag(OverlayFlag.defaultFlag);
      if (mounted) setState(() => _mode = _OverlayMode.recording);
      await _voiceService.startRecording();
    } catch (_) {
      if (mounted)
        setState(() {
          _isRecording = false;
          _mode = _OverlayMode.notificationBar;
        });
      _exitRecording();
    }
  }

  Future<void> _stopOverlayRecording() async {
    if (!_isRecording) return;
    HapticFeedback.mediumImpact();
    setState(() => _isRecording = false);
    try {
      final ab = await _voiceService.stopRecording();
      if (ab != null) {
        final t = await _voiceService.transcribeAudio(ab);
        if (mounted) _input.text = t;
      }
    } catch (_) {}
    _exitRecording();
  }

  Future<void> _exitRecording() async {
    await FlutterOverlayWindow.updateFlag(OverlayFlag.focusPointer);
    if (mounted)
      setState(() {
        _mode = _OverlayMode.notificationBar;
        _isRecording = false;
      });
    _resizeToContent();
  }

  // ── build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    child: switch (_mode) {
      _OverlayMode.notificationBar => _buildBar(context),
      _OverlayMode.selecting => _buildSelector(context),
      _OverlayMode.recording => _buildRecordingUI(context),
    },
  );

  Widget _buildSelector(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Stack(
      children: [
        if (_screenshot != null)
          Positioned.fill(
            child: Image.memory(
              _screenshot!,
              fit: BoxFit.fill,
              width: size.width,
              height: size.height,
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

  Widget _buildRecordingUI(BuildContext context) => Container(
    color: Colors.black.withValues(alpha: 0.90),
    child: Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.mic, color: _kRed, size: 56),
          const SizedBox(height: 24),
          const Text(
            'Listening…',
            style: TextStyle(
              color: _kWhite,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap to stop',
            style: TextStyle(
              color: _kWhite.withValues(alpha: 0.4),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 48),
          OutlinedButton.icon(
            onPressed: _stopOverlayRecording,
            icon: const Icon(Icons.stop, size: 16),
            label: const Text(
              'STOP',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.1,
              ),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: _kWhite.withValues(alpha: 0.6),
              side: BorderSide(color: _kWhite.withValues(alpha: 0.2)),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  // ─────────────────────────────────────────────────────────────────────────
  //  Hybrid capsule bar with conversation history
  //
  //  - Idle: single compact row (status • input • send)
  //  - Messages: scrollable history appears ABOVE the row (max 6 turns)
  //
  //  The tree is:
  //    Align(topCenter)
  //      └─ Padding(top: 12)
  //           └─ Material(key: _colKey)
  //                └─ Container(width: 360, pad: 10v)
  //                     └─ Column(mainAxisSize: min)
  //                          ├─ [_buildMessages() — scrollable, max 6]
  //                          ├─ SizedBox(8)
  //                          └─ Row (always) [status • input • send]
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildBar(BuildContext context) {
    final isBusy = _agent.loading || _agent.booting;

    return OverflowBox(
      alignment: Alignment.topCenter,
      minWidth: 360,
      maxWidth: 360,
      minHeight: 0,
      maxHeight: double.infinity,
      child: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Material(
          key: _colKey,
          color: Colors.transparent,
          child: Container(
            width: 360,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: _kBg,
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.6),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── conversation messages ────────────────
                if (_agent.messages.isNotEmpty) ...[
                  _buildMessages(),
                  const SizedBox(height: 8),
                ],

                // ── single compact row ──────────────────
                Row(
                  children: [
                    // status
                    Row(
                      children: [
                        const Text(
                          '✦ ',
                          style: TextStyle(color: _kWhite, fontSize: 14),
                        ),
                        Text(
                          isBusy ? 'Running agents' : 'Ready',
                          style: const TextStyle(
                            color: _kWhite,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(width: 12),

                    // input capsule
                    Expanded(
                      child: Container(
                        height: 42,
                        decoration: BoxDecoration(
                          color: _kPill,
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.15),
                          ),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _input,
                                cursorColor: _kWhite,
                                style: const TextStyle(
                                  color: _kWhite,
                                  fontSize: 13,
                                ),
                                decoration: const InputDecoration(
                                  border: InputBorder.none,
                                ),
                              ),
                            ),
                            GestureDetector(
                              onTap: _pickAndAttachFile,
                              child: Container(
                                width: 30,
                                height: 30,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(color: _kWhite),
                                ),
                                child: const Icon(
                                  Icons.add,
                                  size: 16,
                                  color: _kWhite,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(width: 10),

                    // send button
                    GestureDetector(
                      onTap: _send,
                      child: Container(
                        width: 46,
                        height: 46,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: _kWhite,
                        ),
                        child: const Icon(
                          Icons.north_east_rounded,
                          color: _kBg,
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  //  Scrollable bubble-chat history
  //  Shows up to the 6 most recent turns inside a capped scroll box.
  // ───────────────────────────────────────────────────────────────────────────
  Widget _buildMessages() {
    final msgs = _agent.messages.length > 6
        ? _agent.messages.sublist(_agent.messages.length - 6)
        : _agent.messages;
    if (msgs.isEmpty) return const SizedBox();

    return ListView.builder(
        controller: _scrollCtrl,
        shrinkWrap: true,
        reverse: true,
        itemCount: msgs.length,
        itemBuilder: (context, i) {
          final msg = msgs[msgs.length - 1 - i];
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Align(
              alignment:
                  msg.fromUser ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: msg.fromUser
                      ? _kWhite.withValues(alpha: 0.9)
                      : _kPill,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: msg.fromUser
                    ? Text(
                        msg.text,
                        style: const TextStyle(
                          color: _kBg,
                          fontSize: 12,
                          height: 1.35,
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (msg.thinking != null) ...[
                            Text(
                              msg.thinking!,
                              style: TextStyle(
                                color: _kWhite.withValues(alpha: 0.5),
                                fontSize: 11,
                                fontStyle: FontStyle.italic,
                                height: 1.35,
                              ),
                            ),
                            const SizedBox(height: 4),
                          ],
                          Text(
                            msg.text,
                            style: const TextStyle(
                              color: _kWhite,
                              fontSize: 12,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          );
        },
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
    final ov = Paint()..color = Colors.black.withValues(alpha: 0.35);
    if (selectionRect != null) {
      canvas.drawPath(
        Path.combine(
          PathOperation.difference,
          Path()..addRect(Offset.zero & size),
          Path()..addRect(selectionRect!),
        ),
        ov,
      );
    } else if (points.length > 1) {
      canvas.drawRect(Offset.zero & size, ov);
    }
    if (points.length > 1) {
      canvas.drawPath(
        Path()..addPolygon(points, false),
        Paint()
          ..color = Colors.white
          ..strokeWidth = 3
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _LassoPainter old) =>
      old.points != points || old.selectionRect != selectionRect;
}
