import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:wrangl_native/wrangl_native.dart';

import '../agent/gemma_client.dart';
import '../agent/harness/harness.dart';
import '../agent/harness/tool.dart';
import '../agent/model_config.dart';
import '../features/voice/voice_input_service.dart';

// ─── Palette ──────────────────────────────────────────────────────────────────
const _kRed = Color(0xFFFF2200);
const _kWhite = Color(0xFFF0EFEB);
const _kBg = Color(0xFF111111);
const _kPill = Color(0xFF1E1E1E);

// ─── Layout ───────────────────────────────────────────────────────────────────
/// Extra vertical room added to the resize so shadows/corners never clip.
const double _kWindowVPad = 60.0;

// ─────────────────────────────────────────────────────────────────────────────

enum _OverlayMode { notificationBar, selecting, recording }

class _Msg {
  final bool fromUser;
  final String text;
  final String? thinking;
  _Msg(this.fromUser, this.text, {this.thinking});
}

// ─── Agent ────────────────────────────────────────────────────────────────────
class _OverlayAgent extends ChangeNotifier {
  GemmaModelClient? _client;
  WranglHarness? _harness;

  Uint8List? pendingImage;
  bool loading = false;
  bool booting = false;
  bool ready = false;
  String? error;
  String? lastThink;
  final List<_Msg> messages = [];
  final List<AgentStep> steps = [];
  final CancellationToken _cancelToken = CancellationToken();
  int _turnCount = 0;

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

  Future<void> reloadModel() async {
    _client?.dispose();
    _client = null;
    _harness = null;
    ready = false;
    booting = false;
    await ensureLoaded();
  }

  Future<String> _complete({
    required String system,
    required List<Map<String, dynamic>> history,
    Uint8List? image,
    int maxTokens = 512,
  }) async {
    final raw = await _client!.complete(
      system,
      history,
      maxTokens: maxTokens,
      image: image,
    );
    lastThink = null;
    final thinkMatch =
        RegExp(r'<think>(.*?)</think>', dotAll: true).firstMatch(raw);
    if (thinkMatch != null) {
      lastThink = thinkMatch.group(1)!.trim();
    }
    return raw;
  }

  void cancelCurrentTask() {
    _cancelToken.cancel();
    steps.clear();
    loading = false;
    notifyListeners();
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
    if (prior.length > 1) prior.removeRange(0, prior.length - 1);
    messages.add(_Msg(true, text));
    steps.clear();
    loading = true;
    notifyListeners();
    lastThink = null;
    try {
      final reply = await _harness!.handle(
        text,
        image: image,
        priorTurns: prior,
        onStep: (s) {
          steps.add(s);
          notifyListeners();
        },
        cancelToken: _cancelToken,
      );
      messages.add(_Msg(false, reply, thinking: lastThink));
    } catch (e) {
      messages.add(_Msg(false, 'Error: $e'));
    } finally {
      loading = false;
      _turnCount++;
      if (_turnCount >= 3) {
        _turnCount = 0;
        reloadModel();
      }
      if (messages.length > 4) {
        messages.removeRange(0, messages.length - 4);
      }
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _client?.dispose();
    super.dispose();
  }
}

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
  final _agent = _OverlayAgent();
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
  // The capsule (Material, key: _colKey) lays out at its natural size — a
  // single Row with fixed-height children, so the height is deterministic.
  // After the first frame we read box.size.height, add the outer Padding top
  // (12 px) and a generous safety margin, then call resizeOverlay.
  // ─────────────────────────────────────────────────────────────────────────
  void _resizeToContent() {
    // Two-frame delay: first frame finishes layout, second reads the size
    // after the RenderObject tree has fully settled.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        final ctx = _colKey.currentContext;
        if (ctx == null) return;
        final box = ctx.findRenderObject() as RenderBox?;
        if (box == null || !box.hasSize) return;

        // Measured card height + outer top pad + safety margin.
        const outerTopPad = 12.0; // matches Padding(top: 12) in _buildBar
        final totalH = box.size.height + outerTopPad + _kWindowVPad;

        await FlutterOverlayWindow.resizeOverlay(360, totalH.ceil(), false);
      });
    });
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
      if (_agent.ready && !_agent.loading) {
        _agent.removeListener(l);
        if (_input.text == text) _send();
      }
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

    return Align(
      alignment: Alignment.topCenter,
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

    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 140),
      child: ListView.builder(
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
      ),
    );
  }
}

// ─── Status line ──────────────────────────────────────────────────────────────
class _StatusLine extends StatelessWidget {
  final String text;
  final Color color;
  const _StatusLine({required this.text, required this.color});

  static const _base = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    fontFamily: 'monospace',
    letterSpacing: 0.2,
  );

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text('✦ ', style: _base.copyWith(color: color)),
      Text(text, style: _base.copyWith(color: color)),
    ],
  );
}

// ─── Clear image chip ─────────────────────────────────────────────────────────
class _ClearImageChip extends StatelessWidget {
  final VoidCallback onTap;
  const _ClearImageChip({required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: _kRed.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _kRed, width: 1),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.close, size: 10, color: _kWhite),
          SizedBox(width: 3),
          Text(
            'Clear',
            style: TextStyle(
              color: _kWhite,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    ),
  );
}

// ─── Reply bubble ─────────────────────────────────────────────────────────────
class _ReplyBubble extends StatelessWidget {
  final String text;
  const _ReplyBubble({required this.text});
  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxHeight: 120),
    child: SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: _TypewriterText(
        text: text,
        style: const TextStyle(
          color: _kWhite,
          fontSize: 12,
          fontWeight: FontWeight.w400,
          height: 1.45,
          fontFamily: 'monospace',
        ),
      ),
    ),
  );
}

// ─── Cycling terminal status ──────────────────────────────────────────────────
class _CyclingTerminalStatus extends StatefulWidget {
  final bool isRunning, isError;
  final String? errorText;
  const _CyclingTerminalStatus({
    required this.isRunning,
    required this.isError,
    this.errorText,
  });
  @override
  State<_CyclingTerminalStatus> createState() => _CyclingTerminalStatusState();
}

class _CyclingTerminalStatusState extends State<_CyclingTerminalStatus> {
  static const _msgs = [
    'Running agents',
    'Analyzing context',
    'Wrangling loops',
  ];
  int _i = 0;
  String _shown = '';
  Timer? _ct, _tt;
  bool _del = false;
  int _ci = 0;

  @override
  void initState() {
    super.initState();
    if (widget.isRunning)
      _go();
    else
      _shown = widget.isError ? (widget.errorText ?? 'Error') : 'Ready';
  }

  @override
  void didUpdateWidget(covariant _CyclingTerminalStatus old) {
    super.didUpdateWidget(old);
    if (widget.isRunning != old.isRunning ||
        widget.isError != old.isError ||
        widget.errorText != old.errorText) {
      _stop();
      if (widget.isRunning) {
        _i = 0;
        _del = false;
        _ci = 0;
        _shown = '';
        _go();
      } else
        setState(
          () =>
              _shown = widget.isError ? (widget.errorText ?? 'Error') : 'Ready',
        );
    }
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  void _stop() {
    _ct?.cancel();
    _tt?.cancel();
  }

  void _go() {
    _tt?.cancel();
    final full = _msgs[_i];
    _tt = Timer(Duration(milliseconds: _del ? 36 : 68), () {
      if (!mounted) return;
      setState(() {
        if (!_del) {
          if (_ci < full.length) {
            _ci++;
            _shown = full.substring(0, _ci);
            _go();
          } else {
            _ct = Timer(const Duration(seconds: 2), () {
              if (!mounted) return;
              setState(() {
                _del = true;
                _go();
              });
            });
          }
        } else {
          if (_ci > 0) {
            _ci--;
            _shown = full.substring(0, _ci);
            _go();
          } else {
            _del = false;
            _i = (_i + 1) % _msgs.length;
            _go();
          }
        }
      });
    });
  }

  static const _base = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    fontFamily: 'monospace',
    letterSpacing: 0.2,
  );

  @override
  Widget build(BuildContext context) {
    final col = widget.isError ? _kRed : _kWhite;
    final style = _base.copyWith(color: col);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('✦ ', style: style),
        Text(_shown, style: style),
        if (widget.isRunning) _BlinkingCursor(style: style),
      ],
    );
  }
}

// ─── Blinking cursor ──────────────────────────────────────────────────────────
class _BlinkingCursor extends StatefulWidget {
  final TextStyle style;
  const _BlinkingCursor({required this.style});
  @override
  State<_BlinkingCursor> createState() => _BlinkingCursorState();
}

class _BlinkingCursorState extends State<_BlinkingCursor>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 500),
  )..repeat(reverse: true);
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _c,
    child: Text('_', style: widget.style),
  );
}

// ─── Typewriter text ──────────────────────────────────────────────────────────
class _TypewriterText extends StatefulWidget {
  final String text;
  final TextStyle style;
  const _TypewriterText({required this.text, required this.style});
  @override
  State<_TypewriterText> createState() => _TypewriterTextState();
}

class _TypewriterTextState extends State<_TypewriterText> {
  String _s = '';
  Timer? _t;
  int _i = 0;
  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(covariant _TypewriterText old) {
    super.didUpdateWidget(old);
    if (widget.text != old.text) _start();
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  void _start() {
    _t?.cancel();
    _i = 0;
    _s = '';
    _t = Timer.periodic(const Duration(milliseconds: 14), (_) {
      if (_i < widget.text.length) {
        setState(() {
          _s += widget.text[_i];
          _i++;
        });
      } else {
        _t?.cancel();
      }
    });
  }

  @override
  Widget build(BuildContext context) => Text(_s, style: widget.style);
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

// ─── Composer ─────────────────────────────────────────────────────────────────
class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSend, onAddFile;
  final VoidCallback? onMicTap;
  final bool enabled, isLoading;

  const _Composer({
    required this.controller,
    required this.onSend,
    required this.onAddFile,
    this.onMicTap,
    required this.enabled,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    final active = enabled ? _kWhite : _kWhite.withValues(alpha: 0.28);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // ── pill text field ─────────────────────────────────────────────────
        Expanded(
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            decoration: BoxDecoration(
              color: _kPill,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    enabled: enabled,
                    onSubmitted: enabled ? (_) => onSend() : null,
                    cursorColor: _kWhite,
                    cursorWidth: 1.8,
                    style: const TextStyle(
                      color: _kWhite,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      fontFamily: 'monospace',
                      height: 1.0,
                    ),
                    decoration: InputDecoration(
                      hintText: enabled ? 'Message…' : 'Processing…',
                      hintStyle: TextStyle(
                        color: _kWhite.withValues(alpha: 0.35),
                        fontSize: 13,
                        fontFamily: 'monospace',
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                    ),
                  ),
                ),

                // mic
                if (onMicTap != null)
                  GestureDetector(
                    onTap: enabled ? onMicTap : null,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Icon(
                        Icons.keyboard_voice_rounded,
                        color: active,
                        size: 20,
                      ),
                    ),
                  ),

                // circle + button
                GestureDetector(
                  onTap: enabled ? onAddFile : null,
                  child: Container(
                    width: 34,
                    height: 34,
                    margin: const EdgeInsets.only(right: 5),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: active, width: 1.6),
                    ),
                    child: Icon(Icons.add, color: active, size: 20),
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(width: 8),

        // ── send button ─────────────────────────────────────────────────────
        GestureDetector(
          onTap: enabled ? onSend : null,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: enabled ? _kWhite : _kWhite.withValues(alpha: 0.20),
            ),
            child: isLoading
                ? Padding(
                    padding: const EdgeInsets.all(10),
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: _kBg,
                    ),
                  )
                : const Icon(Icons.north_east_rounded, color: _kBg, size: 20),
          ),
        ),
      ],
    );
  }
}
