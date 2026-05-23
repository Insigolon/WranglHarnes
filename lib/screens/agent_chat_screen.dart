// lib/screens/agent_chat_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../agent/agent_provider.dart';
import '../chatui.dart';

class AgentChatScreen extends StatefulWidget {
  const AgentChatScreen({super.key});

  @override
  State<AgentChatScreen> createState() => _AgentChatScreenState();
}

class _AgentChatScreenState extends State<AgentChatScreen>
    with WidgetsBindingObserver {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  int _lastMessageCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      context.read<AgentProvider>().flushMemory();
    }
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    context.read<AgentProvider>().sendMessage(text);
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  List<WranglChatMessage> _mapMessages(List<ChatMessage> messages) {
    return messages.map(_toWranglMessage).toList();
  }

  WranglChatMessage _toWranglMessage(ChatMessage message) {
    final time = message.timestamp;
    final stamp =
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    if (message.isUser) {
      return WranglChatMessage(
        sender: 'YOU',
        stamp: stamp,
        body: message.text,
        fromUser: true,
      );
    }
    final sender = message.skillUsed != null
        ? 'WRANGL · ${message.skillUsed!.toUpperCase()}'
        : 'WRANGL';
    return WranglChatMessage(sender: sender, stamp: stamp, body: message.text);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AgentProvider>(
      builder: (context, provider, _) {
        if (provider.messages.length != _lastMessageCount) {
          _lastMessageCount = provider.messages.length;
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _scrollToBottom(),
          );
        }

        Widget? overlay;
        if (provider.status == AgentStatus.initialising) {
          overlay = const _StatusOverlay(
            icon: Icons.settings_suggest,
            label: 'STARTING AGENT SIDECAR',
          );
        } else if (provider.status == AgentStatus.error &&
            provider.messages.isEmpty) {
          overlay = _StatusOverlay(
            icon: Icons.error_outline,
            label: provider.errorMessage ?? 'UNKNOWN ERROR',
            actionLabel: 'RETRY',
            onAction: () => provider.init(),
          );
        }

        return WranglChatScaffold(
          messages: _mapMessages(provider.messages),
          controller: _controller,
          scrollController: _scrollController,
          onSend: _send,
          inputEnabled: provider.status == AgentStatus.ready,
          isLoading: provider.status == AgentStatus.loading,
          overlay: overlay,
          onBrain: () => _showBrainSheet(context),
          onFlush: () async {
            final digest = await provider.flushMemory();
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  digest != null ? 'Memory updated' : 'Nothing new to distil',
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showBrainSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF101010),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => Consumer<AgentProvider>(
        builder: (_, provider, __) {
          final brain = provider.brainSnapshot;
          return Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'SECOND BRAIN',
                  style: TextStyle(
                    color: Color(0xFFE8E7E3),
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${brain.totalInsights} insights across ${brain.topics.length} topics',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.72),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Divider(color: Color(0xFF4B4B4B)),
                Expanded(
                  child: SingleChildScrollView(
                    child: Text(
                      brain.summary,
                      style: const TextStyle(
                        color: Color(0xFFEAEAEA),
                        fontFamily: 'monospace',
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _StatusOverlay extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _StatusOverlay({
    required this.icon,
    required this.label,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black.withOpacity(0.72),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 40, color: const Color(0xFFE8E7E3)),
                const SizedBox(height: 16),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFFE8E7E3),
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
                if (actionLabel != null && onAction != null) ...[
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: onAction,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFE8E7E3),
                      foregroundColor: const Color(0xFF111111),
                    ),
                    child: Text(actionLabel!),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
