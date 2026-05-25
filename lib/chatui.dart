import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';

/// Display model for a single line in the Wrangl chat transcript.
class WranglChatMessage {
  final String sender;
  final String stamp;
  final String body;
  final bool fromUser;

  const WranglChatMessage({
    required this.sender,
    required this.stamp,
    required this.body,
    this.fromUser = false,
  });
}

// ─── Design tokens ───────────────────────────────────────────────────────────
const _kWhite = Color(0xFFF0EFEB);
const _kOffWhite = Color(0xFFE2E1DD);
const _kBlack = Color(0xFF0D0D0D);
const _kRed = Color(0xFFFF2200);
const _kGray = Color(0xFF888888);
const _kGrayDim = Color(0xFF2A2A2A);

// ─── WranglChatScaffold ──────────────────────────────────────────────────────
/// Transparent blurred-overlay chat layout.
/// Place inside a [WranglChatOverlay] — it renders directly over whatever
/// is behind it using a BackdropFilter blur + dark scrim.
class WranglChatScaffold extends StatelessWidget {
  final List<WranglChatMessage> messages;
  final TextEditingController controller;
  final ScrollController scrollController;
  final VoidCallback onSend;
  final bool inputEnabled;
  final bool isLoading;
  final VoidCallback? onClose;
  final VoidCallback? onBrain;
  final VoidCallback? onFlush;
  final Widget? overlay;

  const WranglChatScaffold({
    super.key,
    required this.messages,
    required this.controller,
    required this.scrollController,
    required this.onSend,
    this.inputEnabled = true,
    this.isLoading = false,
    this.onClose,
    this.onBrain,
    this.onFlush,
    this.overlay,
  });

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Stack(
      children: [
        // ── blur + scrim ──────────────────────────────────────────
        Positioned.fill(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: Container(color: Colors.black.withOpacity(0.52)),
          ),
        ),

        // ── top bar (minimal chrome) ──────────────────────────────
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: _TopChrome(isLoading: isLoading, onClose: onClose),
        ),

        // ── message list ──────────────────────────────────────────
        Positioned.fill(
          child: Padding(
            // leave room for top chrome and bottom composer
            padding: EdgeInsets.fromLTRB(0, 60, 0, 84 + bottom),
            child: messages.isEmpty
                ? const _EmptyHint()
                : _FloatingList(
                    messages: messages,
                    scrollController: scrollController,
                  ),
          ),
        ),

        // ── composer ─────────────────────────────────────────────
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: _FloatingComposer(
            controller: controller,
            onSend: onSend,
            enabled: inputEnabled && !isLoading,
            isLoading: isLoading,
          ),
        ),

        // ── status / error overlay ────────────────────────────────
        if (overlay != null) Positioned.fill(child: overlay!),
      ],
    );
  }
}

// ─── Top chrome ──────────────────────────────────────────────────────────────

class _TopChrome extends StatelessWidget {
  final bool isLoading;
  final VoidCallback? onClose;

  const _TopChrome({required this.isLoading, this.onClose});

  @override
  Widget build(BuildContext context) {
    // Extra top padding so the row sits below the status bar text
    final statusBarH = MediaQuery.of(context).padding.top;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, statusBarH + 10, 16, 0),
      child: Row(
        children: [
          const Text(
            'WRANGL',
            style: TextStyle(
              color: _kWhite,
              fontSize: 20,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
              height: 1,
            ),
          ),
          const SizedBox(width: 10),
          if (isLoading)
            const SizedBox(
              width: 10,
              height: 10,
              child: CircularProgressIndicator(strokeWidth: 2, color: _kRed),
            )
          else
            Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                color: _kRed,
                shape: BoxShape.circle,
              ),
            ),
          const Spacer(),
          if (onClose != null)
            GestureDetector(
              onTap: onClose,
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: _kWhite.withOpacity(0.4)),
                ),
                child: const Icon(Icons.close, color: _kWhite, size: 14),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Floating message list ────────────────────────────────────────────────────

class _FloatingList extends StatelessWidget {
  final List<WranglChatMessage> messages;
  final ScrollController scrollController;

  const _FloatingList({required this.messages, required this.scrollController});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      itemCount: messages.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _FloatingBubble(message: messages[i], index: i),
    );
  }
}

class _FloatingBubble extends StatelessWidget {
  final WranglChatMessage message;
  final int index;

  const _FloatingBubble({required this.message, required this.index});

  @override
  Widget build(BuildContext context) {
    final isUser = message.fromUser;
    final maxW = MediaQuery.of(context).size.width * 0.76;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxW),
        child: Container(
          decoration: BoxDecoration(
            color: isUser ? _kWhite : _kGrayDim.withOpacity(0.72),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(isUser ? 16 : 3),
              bottomRight: Radius.circular(isUser ? 3 : 16),
            ),
            // subtle glass border on AI bubbles
            border: isUser
                ? null
                : Border.all(color: _kWhite.withOpacity(0.08)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.22),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(isUser ? 16 : 3),
              bottomRight: Radius.circular(isUser ? 3 : 16),
            ),
            child: BackdropFilter(
              filter: isUser
                  ? ImageFilter.blur(sigmaX: 0, sigmaY: 0)
                  : ImageFilter.blur(sigmaX: 4, sigmaY: 4),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 11),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          message.sender,
                          style: TextStyle(
                            color: isUser ? _kBlack.withOpacity(0.55) : _kGray,
                            fontSize: 8,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.5,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          message.stamp,
                          style: TextStyle(
                            color: isUser
                                ? _kBlack.withOpacity(0.35)
                                : _kGray.withOpacity(0.6),
                            fontSize: 8,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      message.body,
                      style: TextStyle(
                        color: isUser ? _kBlack : _kWhite,
                        fontSize: 14,
                        fontWeight: isUser ? FontWeight.w700 : FontWeight.w500,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Empty hint ───────────────────────────────────────────────────────────────

class _EmptyHint extends StatelessWidget {
  const _EmptyHint();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 64,
            height: 64,
            child: CustomPaint(painter: _DotGridPainter()),
          ),
          const SizedBox(height: 16),
          Text(
            'TRANSMIT\nSIGNAL',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _kWhite.withOpacity(0.3),
              fontSize: 18,
              fontWeight: FontWeight.w900,
              height: 0.95,
              letterSpacing: -0.3,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Floating composer ────────────────────────────────────────────────────────

class _FloatingComposer extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  final bool enabled;
  final bool isLoading;

  const _FloatingComposer({
    required this.controller,
    required this.onSend,
    required this.enabled,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          color: _kWhite.withOpacity(0.12),
          padding: EdgeInsets.fromLTRB(16, 10, 16, 14 + bottom),
          child: Row(
            children: [
              // input pill
              Expanded(
                child: Container(
                  height: 48,
                  decoration: BoxDecoration(
                    color: _kWhite.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: TextField(
                    controller: controller,
                    enabled: enabled,
                    onSubmitted: enabled ? (_) => onSend() : null,
                    cursorColor: _kRed,
                    style: const TextStyle(
                      color: _kBlack,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Message...',
                      hintStyle: TextStyle(
                        color: _kBlack.withOpacity(0.38),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 14,
                      ),
                      border: InputBorder.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // circular send button — matches wireframe
              GestureDetector(
                onTap: enabled ? onSend : null,
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: enabled ? _kWhite : _kWhite.withOpacity(0.3),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.25),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: isLoading
                      ? const Padding(
                          padding: EdgeInsets.all(14),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: _kBlack,
                          ),
                        )
                      : const Icon(
                          Icons.arrow_upward,
                          color: _kBlack,
                          size: 20,
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Painters ─────────────────────────────────────────────────────────────────

class _DotGridPainter extends CustomPainter {
  const _DotGridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    const cols = 6;
    const rows = 6;
    final cw = size.width / cols;
    final rh = size.height / rows;
    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        final on = math.Random(r * 13 + c * 29).nextBool();
        paint.color = on
            ? _kWhite.withOpacity(0.35)
            : _kWhite.withOpacity(0.08);
        canvas.drawCircle(
          Offset(cw * c + cw / 2, rh * r + rh / 2),
          cw * 0.26,
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter _) => false;
}

// ─── WranglChatOverlay ───────────────────────────────────────────────────────
/// Full-screen overlay — place this in a Stack over your launcher.
/// Fades in/out via [visible]; blur comes from [WranglChatScaffold].
class WranglChatOverlay extends StatefulWidget {
  final bool visible;
  final List<WranglChatMessage> messages;
  final TextEditingController controller;
  final ScrollController scrollController;
  final VoidCallback onSend;
  final bool inputEnabled;
  final bool isLoading;
  final VoidCallback? onClose;
  final VoidCallback? onBrain;
  final VoidCallback? onFlush;
  final Widget? overlay;

  const WranglChatOverlay({
    super.key,
    required this.visible,
    required this.messages,
    required this.controller,
    required this.scrollController,
    required this.onSend,
    this.inputEnabled = true,
    this.isLoading = false,
    this.onClose,
    this.onBrain,
    this.onFlush,
    this.overlay,
  });

  @override
  State<WranglChatOverlay> createState() => _WranglChatOverlayState();
}

class _WranglChatOverlayState extends State<WranglChatOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
  );
  late final Animation<double> _fade = CurvedAnimation(
    parent: _ctrl,
    curve: Curves.easeOut,
    reverseCurve: Curves.easeIn,
  );

  @override
  void didUpdateWidget(covariant WranglChatOverlay old) {
    super.didUpdateWidget(old);
    if (widget.visible != old.visible) {
      widget.visible ? _ctrl.forward() : _ctrl.reverse();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, child) {
        if (_ctrl.value == 0) return const SizedBox.shrink();
        return FadeTransition(opacity: _fade, child: child);
      },
      child: WranglChatScaffold(
        messages: widget.messages,
        controller: widget.controller,
        scrollController: widget.scrollController,
        onSend: widget.onSend,
        inputEnabled: widget.inputEnabled,
        isLoading: widget.isLoading,
        onClose: widget.onClose,
        onBrain: widget.onBrain,
        onFlush: widget.onFlush,
        overlay: widget.overlay,
      ),
    );
  }
}
