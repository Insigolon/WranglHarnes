// lib/screens/agent_chat_screen.dart
//
// A plug-in chat screen that connects to the agent harness.
// Add this to your Navigator routes or push it from anywhere.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../agent/agent_provider.dart';

class AgentChatScreen extends StatefulWidget {
  const AgentChatScreen({super.key});

  @override
  State<AgentChatScreen> createState() => _AgentChatScreenState();
}

class _AgentChatScreenState extends State<AgentChatScreen>
    with WidgetsBindingObserver {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();

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

  // Flush memory when app goes to background
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
    Future.delayed(const Duration(milliseconds: 100), _scrollToBottom);
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Agent'),
        actions: [
          IconButton(
            icon: const Icon(Icons.psychology_outlined),
            tooltip: 'Second Brain',
            onPressed: () => _showBrainSheet(context),
          ),
          IconButton(
            icon: const Icon(Icons.memory),
            tooltip: 'Flush memory',
            onPressed: () async {
              final digest = await context.read<AgentProvider>().flushMemory();
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    digest != null ? 'Memory updated' : 'Nothing new to distil',
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: Consumer<AgentProvider>(
        builder: (context, provider, _) {
          if (provider.status == AgentStatus.initialising) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Starting agent sidecar…'),
                ],
              ),
            );
          }

          if (provider.status == AgentStatus.error &&
              provider.messages.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 48,
                      color: Colors.red,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      provider.errorMessage ?? 'Unknown error',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => provider.init(),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            );
          }

          return Column(
            children: [
              Expanded(
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  itemCount: provider.messages.length,
                  itemBuilder: (_, i) => _MessageBubble(provider.messages[i]),
                ),
              ),
              if (provider.status == AgentStatus.loading)
                const LinearProgressIndicator(minHeight: 2),
              _InputBar(
                controller: _controller,
                enabled: provider.status == AgentStatus.ready,
                onSend: _send,
              ),
            ],
          );
        },
      ),
    );
  }

  void _showBrainSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => Consumer<AgentProvider>(
        builder: (_, provider, __) {
          final brain = provider.brainSnapshot;
          if (brain == null) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text('No Second Brain data yet.'),
              ),
            );
          }
          return Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Second Brain',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  '${brain.totalInsights} insights across ${brain.topics.length} topics',
                ),
                const Divider(),
                Expanded(
                  child: ListView(
                    children: [
                      if (brain.summary.isNotEmpty)
                        Text(
                          brain.summary,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                        ),
                    ],
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

// ── Private widgets ───────────────────────────────────────────────────

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  const _MessageBubble(this.message);

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    final theme = Theme.of(context);

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        decoration: BoxDecoration(
          color: isUser
              ? theme.colorScheme.primary
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isUser && message.skillUsed != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '🔧 ${message.skillUsed}',
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            Text(
              message.text,
              style: TextStyle(
                color: isUser
                    ? theme.colorScheme.onPrimary
                    : theme.colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onSend;

  const _InputBar({
    required this.controller,
    required this.enabled,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                enabled: enabled,
                onSubmitted: (_) => onSend(),
                decoration: InputDecoration(
                  hintText: 'Ask anything, or give a task…',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  isDense: true,
                ),
                maxLines: null,
                textInputAction: TextInputAction.send,
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: enabled ? onSend : null,
              icon: const Icon(Icons.send, size: 18),
              label: const Text('Send'),
              style: FilledButton.styleFrom(shape: const StadiumBorder()),
            ),
          ],
        ),
      ),
    );
  }
}
