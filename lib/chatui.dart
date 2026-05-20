import 'dart:math' as math;

import 'package:flutter/material.dart';

class AppStyles {
  static const smallWhite = TextStyle(
    color: Colors.white,
    fontSize: 11,
    fontWeight: FontWeight.w800,
    letterSpacing: 0,
  );

  static const chatBody = TextStyle(
    color: Color(0xFFEAEAEA),
    fontSize: 14,
    fontWeight: FontWeight.w700,
    letterSpacing: 0,
    height: 1.25,
  );
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  final ValueNotifier<List<_ChatMessage>> _messages = ValueNotifier([
    const _ChatMessage(
      sender: 'SYSTEM',
      stamp: '00:01',
      body: 'LOW LIGHT CHANNEL ESTABLISHED. INPUT SIGNAL IS CLEAN.',
    ),
    const _ChatMessage(
      sender: 'WRANGL',
      stamp: '00:03',
      body: 'Ask, draft, route, or decode. I am holding the line.',
    ),
    const _ChatMessage(
      sender: 'YOU',
      stamp: '00:04',
      body: 'Keep it sharp. Show me the useful thread.',
      fromUser: true,
    ),
    const _ChatMessage(
      sender: 'WRANGL',
      stamp: '00:05',
      body: 'Thread pinned. Context window open. Noise floor minimal.',
    ),
  ]);

  final List<_AgentActivity> _agentActivities = const [
    _AgentActivity(
      agent: 'SCOUT',
      action: 'reading the thread',
      detail: 'mapping fresh context',
      accent: Color(0xFFFFCF40),
    ),
    _AgentActivity(
      agent: 'BUILDER',
      action: 'patching the surface',
      detail: 'shaping the next UI move',
      accent: Color(0xFFFF6B35),
    ),
    _AgentActivity(
      agent: 'CHECKER',
      action: 'watching the edges',
      detail: 'testing copy, timing, overflow',
      accent: Color(0xFF6EE7B7),
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _messages.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();

    if (text.isEmpty) return;

    final updatedMessages = List<_ChatMessage>.from(_messages.value)
      ..add(
        _ChatMessage(
          sender: 'YOU',
          stamp: _stamp(),
          body: text,
          fromUser: true,
        ),
      )
      ..add(
        _ChatMessage(
          sender: 'WRANGL',
          stamp: _stamp(offsetSeconds: 1),
          body: 'ACK RECEIVED. I am folding that into the active signal.',
        ),
      );

    _messages.value = updatedMessages;

    _controller.clear();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom();
    });
  }

  String _stamp({int offsetSeconds = 0}) {
    final now = DateTime.now().add(Duration(seconds: offsetSeconds));
    final hour = now.hour.toString().padLeft(2, '0');
    final minute = now.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;

    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isWide = screenWidth >= 760;
    final maxWidth = isWide ? 940.0 : 520.0;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: const Color(0xFF080808),
      body: SafeArea(
        child: Center(
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
                            controller: _controller,
                            scrollController: _scrollController,
                            messages: _messages,
                            agentActivities: _agentActivities,
                            onSend: _send,
                          ),
                        ),
                      ],
                    )
                  : _ChatColumn(
                      controller: _controller,
                      scrollController: _scrollController,
                      messages: _messages,
                      agentActivities: _agentActivities,
                      onSend: _send,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ChatMessage {
  final String sender;
  final String stamp;
  final String body;
  final bool fromUser;

  const _ChatMessage({
    required this.sender,
    required this.stamp,
    required this.body,
    this.fromUser = false,
  });
}

class _AgentActivity {
  final String agent;
  final String action;
  final String detail;
  final Color accent;

  const _AgentActivity({
    required this.agent,
    required this.action,
    required this.detail,
    required this.accent,
  });
}

class _ChatColumn extends StatelessWidget {
  final TextEditingController controller;
  final ScrollController scrollController;
  final ValueNotifier<List<_ChatMessage>> messages;
  final List<_AgentActivity> agentActivities;
  final VoidCallback onSend;

  const _ChatColumn({
    required this.controller,
    required this.scrollController,
    required this.messages,
    required this.agentActivities,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    final compactHeight = MediaQuery.sizeOf(context).height < 650;

    return Column(
      children: [
        RepaintBoundary(
          child: _TopPanel(compact: compactHeight, activities: agentActivities),
        ),
        const SizedBox(height: 14),
        Expanded(
          child: _ConversationPanel(
            controller: controller,
            scrollController: scrollController,
            messages: messages,
            onSend: onSend,
          ),
        ),
      ],
    );
  }
}

class _ConversationPanel extends StatelessWidget {
  final TextEditingController controller;
  final ScrollController scrollController;
  final ValueNotifier<List<_ChatMessage>> messages;
  final VoidCallback onSend;

  const _ConversationPanel({
    required this.controller,
    required this.scrollController,
    required this.messages,
    required this.onSend,
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
            const _SignalHeader(),
            const Divider(height: 1, color: Color(0xFF4B4B4B)),
            Expanded(
              child: ValueListenableBuilder<List<_ChatMessage>>(
                valueListenable: messages,
                builder: (context, value, child) {
                  return ListView.separated(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
                    itemCount: value.length,
                    cacheExtent: 300,
                    addAutomaticKeepAlives: false,
                    addRepaintBoundaries: true,
                    separatorBuilder: (context, index) {
                      return const SizedBox(height: 11);
                    },
                    itemBuilder: (context, index) {
                      final message = value[index];

                      return RepaintBoundary(
                        child: _MessageTile(
                          key: ValueKey(message.stamp + message.body),
                          message: message,
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            _Composer(controller: controller, onSend: onSend),
          ],
        ),
      ),
    );
  }
}

class _MessageTile extends StatelessWidget {
  final _ChatMessage message;

  const _MessageTile({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final maxBubbleWidth = math.min(screenWidth * 0.82, 420.0);

    final isUser = message.fromUser;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxBubbleWidth),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
          decoration: BoxDecoration(
            color: isUser ? const Color(0xFFE8E7E3) : const Color(0xFF171717),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(14),
              topRight: const Radius.circular(14),
              bottomLeft: Radius.circular(isUser ? 14 : 4),
              bottomRight: Radius.circular(isUser ? 4 : 14),
            ),
            border: Border.all(
              color: isUser ? const Color(0xFFE8E7E3) : const Color(0xFF565656),
            ),
          ),
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
                            : Colors.white.withValues(alpha: 0.74),
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  Text(
                    message.stamp,
                    style: TextStyle(
                      color: isUser
                          ? const Color(0xFF151515).withValues(alpha: 0.58)
                          : Colors.white.withValues(alpha: 0.48),
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 7),
              Text(
                message.body,
                style: isUser
                    ? AppStyles.chatBody.copyWith(
                        color: const Color(0xFF111111),
                      )
                    : AppStyles.chatBody,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SideRail extends StatelessWidget {
  const _SideRail();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 64,
      child: Column(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF3F3F3F)),
            ),
            child: Center(
              child: Text(
                'W',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TopPanel extends StatelessWidget {
  final bool compact;
  final List<_AgentActivity> activities;

  const _TopPanel({required this.compact, required this.activities});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ACTIVE AGENTS',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: activities
                .map((activity) => _AgentActivityBadge(activity: activity))
                .toList(),
          ),
        ],
      ),
    );
  }
}

class _AgentActivityBadge extends StatelessWidget {
  final _AgentActivity activity;

  const _AgentActivityBadge({required this.activity});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: activity.accent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: activity.accent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            activity.agent,
            style: TextStyle(
              color: activity.accent,
              fontSize: 10,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            activity.action,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 9,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _SignalHeader extends StatelessWidget {
  const _SignalHeader();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF6EE7B7),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF6EE7B7).withValues(alpha: 0.5),
                  blurRadius: 4,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'SIGNAL ACTIVE',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
          const Spacer(),
          Text(
            'LATENCY: LOW',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _Composer extends StatefulWidget {
  final TextEditingController controller;
  final VoidCallback onSend;

  const _Composer({required this.controller, required this.onSend});

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: const Color(0xFF3F3F3F))),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: widget.controller,
              style: AppStyles.chatBody,
              decoration: InputDecoration(
                hintText: 'Enter command...',
                hintStyle: TextStyle(
                  color: Colors.white.withValues(alpha: 0.3),
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              onSubmitted: (_) => widget.onSend(),
              minLines: 1,
              maxLines: 3,
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: widget.onSend,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFFFCF40).withValues(alpha: 0.2),
              ),
              child: Icon(Icons.send, color: const Color(0xFFFFCF40), size: 18),
            ),
          ),
        ],
      ),
    );
  }
}
