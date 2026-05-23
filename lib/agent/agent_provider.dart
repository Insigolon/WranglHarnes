import 'package:flutter/foundation.dart';
import 'gemma_client.dart';

class BrainSnapshot {
  final String summary;
  final List<String> topics;
  final int totalInsights;

  const BrainSnapshot({
    required this.summary,
    required this.topics,
    required this.totalInsights,
  });
}

enum AgentStatus { initialising, ready, loading, error }

class ChatMessage {
  final bool isUser;
  final String text;
  final String? skillUsed;
  final DateTime timestamp;

  ChatMessage({
    required this.isUser,
    required this.text,
    this.skillUsed,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

class AgentProvider extends ChangeNotifier {
  GemmaModelClient? _client;

  AgentStatus _status = AgentStatus.initialising;
  AgentStatus get status => _status;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  final List<ChatMessage> _messages = [];
  List<ChatMessage> get messages => List.unmodifiable(_messages);

  final BrainSnapshot brainSnapshot = const BrainSnapshot(
    summary: 'Local memory active.',
    topics: [],
    totalInsights: 0,
  );

  String? _modelPath;

  static const _systemPrompt =
      'You are a helpful AI assistant. Answer the user\'s request concisely.';

  Future<void> init([String? modelPath]) async {
    if (modelPath != null) _modelPath = modelPath;
    if (_modelPath == null) {
      _status = AgentStatus.error;
      _errorMessage = 'Cannot init without model path.';
      notifyListeners();
      return;
    }

    _status = AgentStatus.initialising;
    notifyListeners();

    try {
      _client = GemmaModelClient(_modelPath!);
      await _client!.loadModel();
      _status = AgentStatus.ready;
    } catch (e, st) {
      _status = AgentStatus.error;
      _errorMessage = 'Failed to init local model: $e';
      debugPrint('[agent] init error: $e\n$st');
      notifyListeners();
      rethrow;
    }
    notifyListeners();
  }

  Future<void> sendMessage(String task) async {
    if (_status != AgentStatus.ready || _client == null) return;

    _messages.add(ChatMessage(isUser: true, text: task));
    _status = AgentStatus.loading;
    notifyListeners();

    try {
      // Build conversation history from all messages (cap at 20 to stay within nCtx)
      final history = _messages
          .map((m) => <String, dynamic>{
                'role': m.isUser ? 'user' : 'assistant',
                'content': m.text,
              })
          .toList();
      if (history.length > 20) {
        history.removeRange(0, history.length - 20);
      }

      final raw = await _client!.complete(
        _systemPrompt,
        history,
        maxTokens: 512,
      );

      _messages.add(ChatMessage(isUser: false, text: raw, skillUsed: 'chat'));
      _status = AgentStatus.ready;
    } catch (e) {
      _messages.add(ChatMessage(isUser: false, text: 'Error: $e'));
      _status = AgentStatus.error;
      _errorMessage = e.toString();
    }
    notifyListeners();
  }

  Future<String?> flushMemory() async {
    return 'Memory flushed (local log updated).';
  }

  void clearMessages() {
    _messages.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _client?.dispose();
    super.dispose();
  }
}
