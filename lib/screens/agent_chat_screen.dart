// lib/screens/agent_chat_screen.dart
//
// AgentChatOverlay — wraps WranglChatOverlay with full AgentProvider wiring.
// Drop this into any Stack; toggle [visible] to slide the panel in/out.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../agent/agent_provider.dart';
import '../chatui.dart';

// ─── Design tokens (mirrored from scaffold) ──────────────────────────────────
const _kBlack = Color(0xFF0D0D0D);
const _kOffBlack = Color(0xFF111111);
const _kWhite = Color(0xFFEEEEEE);
const _kRed = Color(0xFFFF2200);
const _kGray = Color(0xFF888888);
const _kGrayDim = Color(0xFF333333);
const _kRule = Color(0xFF1E1E1E);

// ─── Public widget ───────────────────────────────────────────────────────────

class AgentChatOverlay extends StatefulWidget {
  final bool visible;
  final VoidCallback? onClose;

  const AgentChatOverlay({super.key, required this.visible, this.onClose});

  @override
  State<AgentChatOverlay> createState() => _AgentChatOverlayState();
}

class _AgentChatOverlayState extends State<AgentChatOverlay>
    with WidgetsBindingObserver {
  final _controller = TextEditingController();
  final _scrollCtrl = ScrollController();
  int _lastCount = 0;

  // ── lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      context.read<AgentProvider>().flushMemory();
    }
  }

  // ── actions ────────────────────────────────────────────────────────────────

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    context.read<AgentProvider>().sendMessage(text);
  }

  void _scrollToBottom() {
    if (!_scrollCtrl.hasClients) return;
    _scrollCtrl.animateTo(
      _scrollCtrl.position.maxScrollExtent,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _handleFlush() async {
    final digest = await context.read<AgentProvider>().flushMemory();
    if (!mounted) return;
    _showToast(digest != null ? 'MEMORY UPDATED' : 'NOTHING NEW TO DISTIL');
  }

  void _showToast(String message) {
    final overlay = Overlay.of(context);
    final entry = OverlayEntry(builder: (_) => _SwitchToast(message: message));
    overlay.insert(entry);
    Future.delayed(const Duration(seconds: 2), entry.remove);
  }

  // ── message mapping ────────────────────────────────────────────────────────

  List<WranglChatMessage> _mapMessages(List<ChatMessage> messages) =>
      messages.map<WranglChatMessage>((m) => _toWrangl(m)).toList();

  WranglChatMessage _toWrangl(ChatMessage m) {
    final t = m.timestamp;
    final stamp =
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    if (m.isUser) {
      return WranglChatMessage(
        sender: 'YOU',
        stamp: stamp,
        body: m.text,
        fromUser: true,
      );
    }
    final sender = m.skillUsed != null
        ? 'WRANGL · ${m.skillUsed!.toUpperCase()}'
        : 'WRANGL';
    return WranglChatMessage(sender: sender, stamp: stamp, body: m.text);
  }

  // ── build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Consumer<AgentProvider>(
      builder: (context, provider, _) {
        // auto-scroll on new messages
        if (provider.messages.length != _lastCount) {
          _lastCount = provider.messages.length;
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _scrollToBottom(),
          );
        }

        // ── status overlay (initialising / hard error) ──
        Widget? statusOverlay;
        if (provider.status == AgentStatus.initialising) {
          statusOverlay = const _SwitchStatusOverlay(
            label: 'STARTING\nAGENT SIDECAR',
          );
        } else if (provider.status == AgentStatus.error &&
            provider.messages.isEmpty) {
          statusOverlay = _SwitchStatusOverlay(
            label: provider.errorMessage ?? 'UNKNOWN ERROR',
            isError: true,
            actionLabel: '[RETRY]',
            onAction: provider.init,
          );
        }

        return WranglChatOverlay(
          visible: widget.visible,
          messages: _mapMessages(provider.messages),
          controller: _controller,
          scrollController: _scrollCtrl,
          onSend: _send,
          inputEnabled: provider.status == AgentStatus.ready,
          isLoading: provider.status == AgentStatus.loading,
          onClose: widget.onClose,
          onBrain: () => _showBrainSheet(context, provider),
          onFlush: _handleFlush,
          overlay: statusOverlay,
        );
      },
    );
  }

  // ── brain sheet ────────────────────────────────────────────────────────────

  void _showBrainSheet(BuildContext context, AgentProvider provider) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _SwitchBrainSheet(provider: provider),
    );
  }
}

// ─── Status overlay (SWITCH aesthetic) ───────────────────────────────────────

class _SwitchStatusOverlay extends StatelessWidget {
  final String label;
  final bool isError;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _SwitchStatusOverlay({
    required this.label,
    this.isError = false,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withOpacity(0.88),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // bracket accent
              Text(
                isError ? '[ERROR]' : '[STATUS]',
                style: TextStyle(
                  color: isError ? _kRed : _kGray,
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 12),
              // red rule
              Container(
                height: 3,
                width: 40,
                color: isError ? _kRed : _kGrayDim,
              ),
              const SizedBox(height: 14),
              Text(
                label,
                style: const TextStyle(
                  color: _kWhite,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  height: 0.95,
                  letterSpacing: -0.5,
                ),
              ),
              if (!isError) ...[
                const SizedBox(height: 20),
                const _SpinnerRow(),
              ],
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: 28),
                GestureDetector(
                  onTap: onAction,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    color: _kRed,
                    child: Text(
                      actionLabel!,
                      style: const TextStyle(
                        color: _kWhite,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SpinnerRow extends StatelessWidget {
  const _SpinnerRow();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          width: 12,
          height: 12,
          child: CircularProgressIndicator(strokeWidth: 2, color: _kGray),
        ),
        const SizedBox(width: 10),
        Text(
          'PLEASE WAIT',
          style: const TextStyle(
            color: _kGray,
            fontSize: 9,
            fontWeight: FontWeight.w900,
            letterSpacing: 2,
          ),
        ),
      ],
    );
  }
}

// ─── Brain sheet (SWITCH aesthetic) ──────────────────────────────────────────

class _SwitchBrainSheet extends StatelessWidget {
  final AgentProvider provider;

  const _SwitchBrainSheet({required this.provider});

  @override
  Widget build(BuildContext context) {
    final brain = provider.brainSnapshot;

    return Container(
      height: MediaQuery.of(context).size.height * 0.72,
      decoration: const BoxDecoration(
        color: _kBlack,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── drag handle ──
          Center(
            child: Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 6),
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: _kGray,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),

          // ── red ticker ──
          Container(
            color: _kRed,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
            child: Row(
              children: [
                const Text(
                  'SECOND BRAIN — MEMORY SNAPSHOT',
                  style: TextStyle(
                    color: _kWhite,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                  ),
                ),
                const Spacer(),
                Text(
                  '[${brain.totalInsights} INSIGHTS]',
                  style: const TextStyle(
                    color: _kWhite,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),

          // ── wordmark row ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Text(
                  'BRAIN',
                  style: TextStyle(
                    color: _kWhite,
                    fontSize: 40,
                    fontWeight: FontWeight.w900,
                    height: 0.9,
                    letterSpacing: -1,
                  ),
                ),
                const SizedBox(width: 10),
                Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Text(
                    '${brain.topics.length} TOPICS',
                    style: const TextStyle(
                      color: _kGray,
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                    ),
                  ),
                ),
              ],
            ),
          ),

          Container(
            margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            height: 2,
            color: _kRule,
          ),

          // ── topic pills ──
          if (brain.topics.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: brain.topics.map((t) => _TopicPill(t)).toList(),
              ),
            ),

          Container(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            height: 2,
            color: _kRule,
          ),

          // ── summary body ──
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
              child: Text(
                brain.summary.isEmpty ? 'NO DATA CAPTURED YET.' : brain.summary,
                style: const TextStyle(
                  color: Color(0xFFAAAAAA),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  height: 1.45,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TopicPill extends StatelessWidget {
  final String label;
  const _TopicPill(this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(border: Border.all(color: _kGrayDim)),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          color: _kGray,
          fontSize: 8,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.5,
        ),
      ),
    );
  }
}

// ─── Toast (replaces SnackBar) ────────────────────────────────────────────────

class _SwitchToast extends StatelessWidget {
  final String message;
  const _SwitchToast({required this.message});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 100,
      left: 24,
      right: 24,
      child: Material(
        color: Colors.transparent,
        child: Container(
          color: _kRed,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Text(
            message,
            style: const TextStyle(
              color: _kWhite,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
            ),
          ),
        ),
      ),
    );
  }
}
