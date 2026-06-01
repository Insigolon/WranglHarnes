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
  //  Resize strategy
  //
  // _buildBar wraps its content in an OverflowBox so the capsule measures at
  // its natural (unclipped) height regardless of the current overlay window
  // size.  After each frame we read the capsule's natural height, resize the
  // native window to fit, and keep re-measuring until two consecutive reads
  // are equal (settled) or we hit the max-iteration guard.  This catches
  // late layout passes from image decode, streaming replies, etc.
  // ─────────────────────────────────────────────────────────────────────────
  static const int _kResizeMaxIter = 5;
  int? _lastAppliedHeight;

  void _resizeToContent() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _settleResize(0);
    });
  }

  Future<void> _settleResize(int iter) async {
    if (!mounted) return;
    if (iter >= _kResizeMaxIter) return;
    final int? h = _measure();
    if (h == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _settleResize(iter + 1);
      });
      return;
    }
    if (_lastAppliedHeight == h) return;
    await FlutterOverlayWindow.resizeOverlay(360, h, false);
    _lastAppliedHeight = h;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _settleResize(iter + 1);
    });
  }

  /// Reads the capsule's current render height and returns the total overlay
  /// height (content + padding + safety margin) clamped to the device screen
  /// height, or null if the layout isn't ready yet.
  int? _measure() {
    final ctx = _colKey.currentContext;
    if (ctx == null) return null;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    const outerTopPad = 12.0;
    final raw = box.size.height + outerTopPad + _kWindowVPad;
    final screenH = _screenDp.height;
    return raw.clamp(0, screenH).ceil();
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
      unawaited(_send());
      return;
    }
    void onChange() {
      _agent.removeListener(onChange);
      if (_agent.ready && !_agent.loading && _input.text == text) {
        unawaited(_send());
      }
    }
    _agent.addListener(onChange);
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
    try {
      final fs = _screenDp;
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
    } catch (e) {
      debugPrint('[selection] enter failed: $e');
    } finally {
      _busy = false;
    }
  }

  Future<void> _exitSelection() async {
    if (_busy) return;
    _busy = true;
    try {
      await FlutterOverlayWindow.updateFlag(OverlayFlag.focusPointer);
      if (mounted) {
        setState(() {
          _mode = _OverlayMode.notificationBar;
          _screenshot = null;
          _lassoPoints = [];
          _cropRect = null;
        });
      }
      _resizeToContent();
    } catch (e) {
      debugPrint('[selection] exit failed: $e');
    } finally {
      _busy = false;
    }
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
    final ui.Image image;
    try {
      final codec = await ui.instantiateImageCodec(
        Uint8List.fromList(_screenshot!),
      );
      final frame = await codec.getNextFrame();
      image = frame.image;
    } catch (e) {
      debugPrint('[crop] failed to decode screenshot: $e');
      if (mounted) {
        setState(() {
          _mode = _OverlayMode.notificationBar;
          _screenshot = null;
          _lassoPoints = [];
          _cropRect = null;
        });
      }
      await FlutterOverlayWindow.updateFlag(OverlayFlag.focusPointer);
      _resizeToContent();
      return;
    }
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
    if (bytes != null && _input.text.isNotEmpty) {
      _agent.pendingImage = bytes.buffer.asUint8List();
    }
    await FlutterOverlayWindow.updateFlag(OverlayFlag.focusPointer);
    if (mounted)
      setState(() {
        _mode = _OverlayMode.notificationBar;
        _screenshot = null;
        _lassoPoints = [];
        _cropRect = null;
      });
    _agent.ensureLoaded();
    if (_input.text.isNotEmpty) await _send();
    _resizeToContent();
  }

  // ── send ──────────────────────────────────────────────────────────────────

  Future<void> _send() async {
    var text = _input.text.trim();
    if (text.isEmpty) return;
    _input.clear();
    if (text.startsWith('/exp')) {
      text = text.substring(4).trim();
      if (text.isEmpty) text = 'Describe what is on my screen';
      await _captureAndSend(text);
      return;
    }
    final image = _agent.pendingImage;
    _agent.pendingImage = null;
    await _agent.send(text, image: image);
  }

  Future<void> _captureAndSend(String prompt) async {
    try {
      await _agent.send(prompt, image: await WranglNative.captureScreen());
    } catch (e) {
      await _agent.send('/exp failed: $e');
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
    child: SafeArea(
      child: SingleChildScrollView(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
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
                const SizedBox(height: 24),
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
        ),
      ),
    ),
  );

  // ─────────────────────────────────────────────────────────────────────────
  //  Hybrid capsule bar with conversation history
  //
  //  - Idle: messages (if any) + input row only
  //  - Busy: a slim status banner appears between messages and the input
  //  - Status is a free-floating row above the input, not packed into it
  //
  //  The tree is:
  //    Align(topCenter)
  //      └─ Padding(top: 12)
  //           └─ Material(key: _colKey)
  //                └─ Container(width: 360, pad: 10v)
  //                     └─ Column(mainAxisSize: min)
  //                          ├─ [_buildMessages() — scrollable, max 55% screen]
  //                          ├─ SizedBox(8)
  //                          ├─ [_buildStatusBar() — only when busy]
  //                          ├─ SizedBox(6) — only when busy
  //                          └─ Row [reset • input • send]
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildBar(BuildContext context) {
    final isBusy = _agent.loading || _agent.booting;
    final hasMessages = _agent.messages.isNotEmpty;
    final screenH = _screenDp.height;
    final messagesCap = math.min(320.0, screenH * 0.55);

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
                if (hasMessages) ...[
                  ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: messagesCap),
                    child: _buildMessages(),
                  ),
                  const SizedBox(height: 8),
                ],

                // ── status banner (only when busy) ───────
                if (isBusy) ...[
                  _buildStatusBar(context),
                  const SizedBox(height: 6),
                ],

                // ── single compact row [reset • input • send] ──
                Row(
                  children: [
                    // reset session button (only when there's something to reset)
                    if (_canReset())
                      _buildResetButton()
                    else
                      const SizedBox(width: 0),

                    if (_canReset()) const SizedBox(width: 8),

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
                                maxLines: 1,
                                textInputAction: TextInputAction.send,
                                cursorColor: _kWhite,
                                style: const TextStyle(
                                  color: _kWhite,
                                  fontSize: 13,
                                ),
                                decoration: const InputDecoration(
                                  border: InputBorder.none,
                                  isDense: true,
                                  contentPadding: EdgeInsets.zero,
                                ),
                                onSubmitted: (_) => unawaited(_send()),
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
                      onTap: () => unawaited(_send()),
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

  bool _canReset() =>
      _agent.messages.isNotEmpty || _agent.pendingImage != null;

  Widget _buildResetButton() {
    return Semantics(
      label: 'New session',
      button: true,
      child: GestureDetector(
        onTap: _confirmResetDialog,
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _kPill,
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.15),
            ),
          ),
          child: Icon(
            Icons.refresh,
            size: 16,
            color: _kWhite.withValues(alpha: 0.6),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBar(BuildContext context) {
    final isBooting = _agent.booting;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _kPill,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(
                _kWhite.withValues(alpha: 0.7),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              isBooting ? 'Loading model…' : 'Running agents…',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _kWhite,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmResetDialog() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: _kBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'New session?',
                style: TextStyle(
                  color: _kWhite,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'This will clear the current conversation.',
                style: TextStyle(color: _kWhite, fontSize: 13),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(color: Color(0xFF888888)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    child: const Text(
                      'Reset',
                      style: TextStyle(
                        color: Color(0xFFFF2200),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (ok != true || !mounted) return;
    _agent.resetSession();
    _input.clear();
    _lastAppliedHeight = null;
    _resizeToContent();
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
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
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
                          maxLines: 6,
                          softWrap: true,
                          overflow: TextOverflow.ellipsis,
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
                                maxLines: 4,
                                softWrap: true,
                                overflow: TextOverflow.ellipsis,
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
                              maxLines: 6,
                              softWrap: true,
                              overflow: TextOverflow.ellipsis,
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
