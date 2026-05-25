// lib/overlay/bubble_overlay.dart
//
// Everything that runs inside the *overlay isolate* — the floating Wrangl
// bubble that sits over other apps, and the chat panel it expands into.
//
// This isolate is separate from the main app, so it owns its own Gemma model
// instance ([_OverlayAgent]) loaded lazily from the on-disk model file the
// downloader already fetched. The collapsed bubble is a tiny system window;
// long-pressing it grows the window to full-screen and shows the chat.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

import '../agent/gemma_client.dart';
import '../agent/harness/harness.dart';
import '../agent/model_config.dart';

// ─── Window sizing ───────────────────────────────────────────────────────────
// The collapsed bubble lives in a small square window; extra room leaves space
// for the drop shadow so it isn't clipped at the window edge.
const double kBubbleWindow = 72;
const double kBubbleDiameter = 60;

// ─── Palette ─────────────────────────────────────────────────────────────────
const _kRed = Color(0xFFFF2200);
const _kWhite = Color(0xFFF0EFEB);
final _kBubbleBlack = Colors.black.withOpacity(0.80); // chat bubbles, per spec
final _kComposer = Colors.black.withOpacity(0.80);

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

  bool loading = false; // a request is in flight
  bool booting = false; // model is loading from disk
  bool ready = false;
  String? error;
  final List<_Msg> messages = [];

  /// Load the model the first time the chat is opened, then build the harness
  /// on top of it. Vision is requested; GemmaModelClient falls back to
  /// text-only if the model file has no vision encoder.
  Future<void> ensureLoaded() async {
    if (ready || booting) return;
    booting = true;
    error = null;
    notifyListeners();
    try {
      final path = await ModelConfig.path();
      _client = GemmaModelClient(path);
      await _client!.loadModel(withVision: true);
      _harness = await WranglHarness.load(_complete);
      ready = true;
    } catch (e) {
      error = '$e';
    } finally {
      booting = false;
      notifyListeners();
    }
  }

  /// Adapter from the harness's [ModelComplete] contract to GemmaModelClient.
  Future<String> _complete({
    required String system,
    required List<Map<String, dynamic>> history,
    Uint8List? image,
    int maxTokens = 512,
  }) {
    return _client!.complete(system, history, maxTokens: maxTokens, image: image);
  }

  Future<void> send(String text) async {
    if (!ready || _harness == null || loading) return;

    // Snapshot the clean conversation so far (text turns only) so the harness
    // keeps multi-turn context, then add the new user message.
    final prior = messages
        .map((m) => <String, dynamic>{
              'role': m.fromUser ? 'user' : 'assistant',
              'content': m.text,
            })
        .toList();
    if (prior.length > 6) prior.removeRange(0, prior.length - 6);

    messages.add(_Msg(true, text));
    loading = true;
    notifyListeners();

    try {
      final reply = await _harness!.handle(text, priorTurns: prior);
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
      // Transparent so the underlying app shows through when collapsed.
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
  bool _expanded = false;
  bool _busy = false; // guards overlapping expand/collapse window resizes

  @override
  void initState() {
    super.initState();
    _agent.addListener(_onAgent);
  }

  @override
  void dispose() {
    _agent.removeListener(_onAgent);
    _agent.dispose();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
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

  Future<void> _expand() async {
    if (_busy || _expanded) return;
    _busy = true;
    HapticFeedback.mediumImpact();
    // Grow the system window to fill the screen and let it take keyboard focus
    // *before* we paint the chat, so nothing gets clipped to the bubble size.
    await FlutterOverlayWindow.resizeOverlay(
      WindowSize.matchParent,
      WindowSize.matchParent,
      false,
    );
    await FlutterOverlayWindow.updateFlag(OverlayFlag.focusPointer);
    if (mounted) setState(() => _expanded = true);
    _busy = false;
    _agent.ensureLoaded();
  }

  Future<void> _collapse() async {
    if (_busy || !_expanded) return;
    _busy = true;
    FocusScope.of(context).unfocus();
    setState(() => _expanded = false);
    // Shrink the window back to the bubble and stop intercepting touches.
    await FlutterOverlayWindow.updateFlag(OverlayFlag.defaultFlag);
    await FlutterOverlayWindow.resizeOverlay(
      kBubbleWindow.toInt(),
      kBubbleWindow.toInt(),
      true,
    );
    _busy = false;
  }

  void _send() {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    _input.clear();
    _agent.send(text);
  }

  // ── build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: _expanded ? _buildChat(context) : _buildBubble(),
    );
  }

  // Collapsed: just the floating circle.
  Widget _buildBubble() {
    return Center(
      child: GestureDetector(
        onLongPress: _expand,
        onTap: _expand,
        child: Container(
          width: kBubbleDiameter,
          height: kBubbleDiameter,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF5C5C5C),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.5),
                blurRadius: 16,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Center(
            child: Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(
                color: _kRed,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Expanded: chat bubbles + composer floating over the current app — no
  // scrim, no header, no close button. Tap anywhere outside the bubbles or
  // the composer to collapse back to the floating circle.
  Widget _buildChat(BuildContext context) {
    final insets = MediaQuery.of(context).viewInsets.bottom;
    final topPad = MediaQuery.of(context).padding.top;
    return Stack(
      children: [
        // Invisible tap-outside-to-dismiss target. HitTestBehavior.opaque is
        // required so the GestureDetector receives taps despite having no
        // painted background.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _collapse,
          ),
        ),

        // Messages.
        Positioned.fill(
          top: topPad + 12,
          bottom: 78 + insets,
          child: _agent.error != null && _agent.messages.isEmpty
              ? _StatusCard(label: _agent.error!, isError: true)
              : _agent.booting && _agent.messages.isEmpty
              ? const _StatusCard(label: 'STARTING AGENT…')
              : ListView.separated(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  itemCount: _agent.messages.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => _Bubble(_agent.messages[i]),
                ),
        ),

        // Composer.
        Positioned(
          left: 12,
          right: 12,
          bottom: 12 + insets,
          child: _Composer(
            controller: _input,
            onSend: _send,
            enabled: _agent.ready && !_agent.loading,
            isLoading: _agent.loading,
          ),
        ),
      ],
    );
  }
}

// ─── Chat bubble (black, 80% opacity) ─────────────────────────────────────────
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
                  color: _kWhite.withOpacity(0.4),
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
                color: enabled ? _kWhite : _kWhite.withOpacity(0.3),
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
