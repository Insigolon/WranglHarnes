import 'dart:math' as math;

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

/// Full-screen Wrangl chat layout (top panel, signal header, transcript, composer).
class WranglChatScaffold extends StatelessWidget {
  final List<WranglChatMessage> messages;
  final TextEditingController controller;
  final ScrollController scrollController;
  final VoidCallback onSend;
  final bool inputEnabled;
  final bool isLoading;
  final Widget? overlay;
  final VoidCallback? onBrain;
  final VoidCallback? onFlush;

  const WranglChatScaffold({
    super.key,
    required this.messages,
    required this.controller,
    required this.scrollController,
    required this.onSend,
    this.inputEnabled = true,
    this.isLoading = false,
    this.overlay,
    this.onBrain,
    this.onFlush,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: const Color(0xFF080808),
      body: SafeArea(
        child: Stack(
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 760;
                final maxWidth = isWide ? 940.0 : 520.0;

                return Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: maxWidth),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        isWide ? 24 : 14,
                        12,
                        isWide ? 24 : 14,
                        14,
                      ),
                      child: isWide
                          ? Row(
                              children: [
                                const _SideRail(),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: _ChatColumn(
                                    controller: controller,
                                    scrollController: scrollController,
                                    messages: messages,
                                    onSend: onSend,
                                    inputEnabled: inputEnabled && !isLoading,
                                    isLoading: isLoading,
                                    onBrain: onBrain,
                                    onFlush: onFlush,
                                  ),
                                ),
                              ],
                            )
                          : _ChatColumn(
                              controller: controller,
                              scrollController: scrollController,
                              messages: messages,
                              onSend: onSend,
                              inputEnabled: inputEnabled && !isLoading,
                              isLoading: isLoading,
                              onBrain: onBrain,
                              onFlush: onFlush,
                            ),
                    ),
                  ),
                );
              },
            ),
            if (overlay != null) Positioned.fill(child: overlay!),
          ],
        ),
      ),
    );
  }
}

class _ChatColumn extends StatelessWidget {
  final TextEditingController controller;
  final ScrollController scrollController;
  final List<WranglChatMessage> messages;
  final VoidCallback onSend;
  final bool inputEnabled;
  final bool isLoading;
  final VoidCallback? onBrain;
  final VoidCallback? onFlush;

  const _ChatColumn({
    required this.controller,
    required this.scrollController,
    required this.messages,
    required this.onSend,
    required this.inputEnabled,
    required this.isLoading,
    this.onBrain,
    this.onFlush,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compactHeight = constraints.maxHeight < 650;

        return Column(
          children: [
            _TopPanel(
              compact: compactHeight,
              onBrain: onBrain,
              onFlush: onFlush,
            ),
            const SizedBox(height: 14),
            Expanded(
              child: _ConversationPanel(
                controller: controller,
                scrollController: scrollController,
                messages: messages,
                onSend: onSend,
                inputEnabled: inputEnabled,
                isLoading: isLoading,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _TopPanel extends StatelessWidget {
  final bool compact;
  final VoidCallback? onBrain;
  final VoidCallback? onFlush;

  const _TopPanel({required this.compact, this.onBrain, this.onFlush});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: compact ? 128 : 154,
      decoration: BoxDecoration(
        color: const Color(0xFFE8E7E3),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.42),
            blurRadius: 24,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Tooltip(
                  message: 'Back',
                  child: _IconDisc(
                    icon: Icons.arrow_back,
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'WRANGL',
                      maxLines: 1,
                      style: TextStyle(
                        color: Color(0xFF111111),
                        fontSize: 42,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0,
                        height: 0.9,
                      ),
                    ),
                  ),
                ),
                if (onBrain != null) ...[
                  const SizedBox(width: 8),
                  Tooltip(
                    message: 'Second Brain',
                    child: _IconDisc(
                      icon: Icons.psychology_outlined,
                      onPressed: onBrain!,
                      light: true,
                    ),
                  ),
                ],
                if (onFlush != null) ...[
                  const SizedBox(width: 8),
                  Tooltip(
                    message: 'Flush memory',
                    child: _IconDisc(
                      icon: Icons.memory,
                      onPressed: onFlush!,
                      light: true,
                    ),
                  ),
                ],
                const SizedBox(width: 8),
                const SizedBox(
                  width: 86,
                  height: 42,
                  child: CustomPaint(painter: _EmblemPainter()),
                ),
              ],
            ),
            const Spacer(),
            if (!compact)
              const Text(
                'CHANNEL WARNING',
                style: TextStyle(
                  color: Color(0xFF161616),
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                ),
              ),
            if (!compact) const SizedBox(height: 3),
            if (!compact)
              Text(
                'HIGH CONTRAST, DENSE SIGNAL, FAST ROUTING. LOW VISIBILITY '
                'NODES MAY DROP PACKETS. STAY INSIDE THE THREAD.',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.black.withOpacity(0.74),
                  fontSize: 8,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                  height: 1.15,
                ),
              ),
            const SizedBox(height: 10),
            Container(
              height: 32,
              decoration: BoxDecoration(
                color: const Color(0xFF111111),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 15),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '141.98\$',
                        style: TextStyle(
                          color: Color(0xFFA7A39A),
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                    Text(
                      'ACTIVE CHAT',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0,
                      ),
                    ),
                    SizedBox(width: 8),
                    Icon(Icons.arrow_forward, color: Colors.white, size: 16),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConversationPanel extends StatelessWidget {
  final TextEditingController controller;
  final ScrollController scrollController;
  final List<WranglChatMessage> messages;
  final VoidCallback onSend;
  final bool inputEnabled;
  final bool isLoading;

  const _ConversationPanel({
    required this.controller,
    required this.scrollController,
    required this.messages,
    required this.onSend,
    required this.inputEnabled,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF101010),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFF3F3F3F)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(21),
        child: Column(
          children: [
            _SignalHeader(isLoading: isLoading),
            const Divider(height: 1, color: Color(0xFF4B4B4B)),
            Expanded(
              child: messages.isEmpty
                  ? Center(
                      child: Text(
                        'TRANSMIT SIGNAL TO OPEN THREAD',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.38),
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0,
                        ),
                      ),
                    )
                  : ListView.separated(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
                      itemCount: messages.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 11),
                      itemBuilder: (context, index) {
                        return _MessageTile(message: messages[index]);
                      },
                    ),
            ),
            _Composer(
              controller: controller,
              onSend: onSend,
              enabled: inputEnabled,
            ),
          ],
        ),
      ),
    );
  }
}

class _SignalHeader extends StatelessWidget {
  final bool isLoading;

  const _SignalHeader({required this.isLoading});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 88,
      child: Row(
        children: [
          const SizedBox(
            width: 94,
            height: 88,
            child: CustomPaint(painter: _GlitchBandsPainter()),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 12, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Administrative region -- active node',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.64),
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Conversation',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 19,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0,
                      height: 1,
                    ),
                  ),
                  const Spacer(),
                  Container(height: 1, color: const Color(0xFF6F6F6F)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'ISO 3166 code',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0,
                          ),
                        ),
                      ),
                      if (isLoading)
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFFE8E7E3),
                          ),
                        )
                      else
                        const Text(
                          'WR-CHAT',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(
            width: 86,
            child: Padding(
              padding: EdgeInsets.only(right: 12),
              child: CustomPaint(painter: _SignalBurstPainter()),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageTile extends StatelessWidget {
  final WranglChatMessage message;

  const _MessageTile({required this.message});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxBubbleWidth = math.min(constraints.maxWidth * 0.82, 420.0);
        final isUser = message.fromUser;

        return Align(
          alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxBubbleWidth),
            child: Container(
              decoration: BoxDecoration(
                color: isUser
                    ? const Color(0xFFE8E7E3)
                    : const Color(0xFF171717),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(14),
                  topRight: const Radius.circular(14),
                  bottomLeft: Radius.circular(isUser ? 14 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 14),
                ),
                border: Border.all(
                  color: isUser
                      ? const Color(0xFFE8E7E3)
                      : const Color(0xFF565656),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            message.sender,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isUser
                                  ? const Color(0xFF151515)
                                  : Colors.white.withOpacity(0.74),
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0,
                            ),
                          ),
                        ),
                        Text(
                          message.stamp,
                          style: TextStyle(
                            color: isUser
                                ? const Color(0xFF151515).withOpacity(0.58)
                                : Colors.white.withOpacity(0.48),
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 7),
                    Text(
                      message.body,
                      style: TextStyle(
                        color: isUser
                            ? const Color(0xFF111111)
                            : const Color(0xFFEAEAEA),
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0,
                        height: 1.25,
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

class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  final bool enabled;

  const _Composer({
    required this.controller,
    required this.onSend,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFF4B4B4B))),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 46,
              decoration: BoxDecoration(
                color: const Color(0xFF0B0B0B),
                borderRadius: BorderRadius.circular(23),
                border: Border.all(color: const Color(0xFF4C4C4C)),
              ),
              child: TextField(
                controller: controller,
                enabled: enabled,
                onSubmitted: enabled ? (_) => onSend() : null,
                cursorColor: Colors.white,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
                decoration: InputDecoration(
                  hintText: 'TRANSMIT SIGNAL',
                  hintStyle: TextStyle(
                    color: Colors.white.withOpacity(0.42),
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 13,
                  ),
                  border: InputBorder.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Tooltip(
            message: 'Send',
            child: _IconDisc(
              icon: Icons.north_east,
              onPressed: enabled ? onSend : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _IconDisc extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final bool light;

  const _IconDisc({
    required this.icon,
    required this.onPressed,
    this.light = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 42,
      height: 42,
      child: IconButton(
        onPressed: onPressed,
        style: IconButton.styleFrom(
          backgroundColor: light
              ? const Color(0xFFD8D7D3)
              : const Color(0xFF111111),
          foregroundColor: light ? const Color(0xFF111111) : Colors.white,
          shape: const CircleBorder(side: BorderSide(color: Color(0xFF696969))),
        ),
        icon: Icon(icon, size: 19),
      ),
    );
  }
}

class _SideRail extends StatelessWidget {
  const _SideRail();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 74,
      decoration: BoxDecoration(
        color: const Color(0xFF0E0E0E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF3F3F3F)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 14),
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 1.2),
            ),
          ),
          const SizedBox(height: 30),
          const Text(
            'Visit',
            style: TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 32),
          const SizedBox(
            height: 180,
            child: CustomPaint(painter: _GlitchBandsPainter(vertical: true)),
          ),
          const Spacer(),
          const RotatedBox(
            quarterTurns: 3,
            child: Text(
              'Wrangl and the active signal region',
              maxLines: 1,
              style: TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
          ),
          const SizedBox(height: 18),
        ],
      ),
    );
  }
}

class _EmblemPainter extends CustomPainter {
  const _EmblemPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF151515)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final fill = Paint()..color = const Color(0xFF151515);
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) * 0.34;

    canvas.drawOval(
      Rect.fromCenter(
        center: center,
        width: size.width * 0.86,
        height: size.height * 0.42,
      ),
      paint,
    );

    final star = Path()
      ..moveTo(center.dx, center.dy - radius)
      ..quadraticBezierTo(
        center.dx + radius * 0.16,
        center.dy - radius * 0.18,
        center.dx + radius,
        center.dy,
      )
      ..quadraticBezierTo(
        center.dx + radius * 0.16,
        center.dy + radius * 0.18,
        center.dx,
        center.dy + radius,
      )
      ..quadraticBezierTo(
        center.dx - radius * 0.16,
        center.dy + radius * 0.18,
        center.dx - radius,
        center.dy,
      )
      ..quadraticBezierTo(
        center.dx - radius * 0.16,
        center.dy - radius * 0.18,
        center.dx,
        center.dy - radius,
      )
      ..close();
    canvas.drawPath(star, fill);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _GlitchBandsPainter extends CustomPainter {
  final bool vertical;

  const _GlitchBandsPainter({this.vertical = false});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    final count = vertical ? 34 : 22;

    canvas.save();
    if (vertical) {
      canvas.translate(size.width / 2, size.height / 2);
      canvas.rotate(math.pi / 2);
      canvas.translate(-size.height / 2, -size.width / 2);
      final swapped = Size(size.height, size.width);
      _drawBands(canvas, swapped, paint, count);
    } else {
      _drawBands(canvas, size, paint, count);
    }
    canvas.restore();
  }

  void _drawBands(Canvas canvas, Size size, Paint paint, int count) {
    for (var i = 0; i < count; i++) {
      final y = size.height * (0.12 + i / (count + 3));
      final wave = math.sin(i * 1.37) * 0.5 + 0.5;
      final x = size.width * (0.04 + wave * 0.22);
      final width = size.width * (0.34 + (1 - wave) * 0.48);
      final height = i.isEven ? 3.0 : 2.0;
      paint.color = i % 4 == 0
          ? const Color(0xFFC8C8C8)
          : const Color(0xFFE6E6E6);
      canvas.drawRect(Rect.fromLTWH(x, y, width, height), paint);

      if (i % 5 == 0) {
        paint.color = const Color(0xFF7A7A7A);
        canvas.drawRect(
          Rect.fromLTWH(x + width * 0.62, y + 4, width * 0.24, 1.5),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GlitchBandsPainter oldDelegate) {
    return oldDelegate.vertical != vertical;
  }
}

class _SignalBurstPainter extends CustomPainter {
  const _SignalBurstPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) * 0.42;
    final paint = Paint()
      ..color = const Color(0xFFE8E7E3)
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.square;

    for (var i = 0; i < 8; i++) {
      final angle = i * math.pi / 4;
      final inner = Offset(
        center.dx + math.cos(angle) * radius * 0.48,
        center.dy + math.sin(angle) * radius * 0.48,
      );
      final outer = Offset(
        center.dx + math.cos(angle) * radius,
        center.dy + math.sin(angle) * radius,
      );
      canvas.drawLine(inner, outer, paint);
    }

    final textPainter = TextPainter(
      text: const TextSpan(
        text: 'LINK',
        style: TextStyle(
          color: Color(0xFFE8E7E3),
          fontSize: 9,
          fontWeight: FontWeight.w900,
          letterSpacing: 0,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(
      canvas,
      Offset(
        center.dx - textPainter.width / 2,
        center.dy - textPainter.height / 2,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
