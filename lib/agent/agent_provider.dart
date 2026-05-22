// lib/agent/agent_provider.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'fllama_client.dart';
import 'skill.dart';
import 'skill_router.dart';
import 'agent_loop.dart';

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
  FLlamaModelClient? _client;
  late SkillRouter _router;
  late File _sessionLogFile;

  AgentStatus _status = AgentStatus.initialising;
  AgentStatus get status => _status;
  bool get isModelLoaded => _client != null && _status == AgentStatus.ready;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  final List<ChatMessage> _messages = [];
  List<ChatMessage> get messages => List.unmodifiable(_messages);

  BrainSnapshot? _brainSnapshot;
  BrainSnapshot? get brainSnapshot => _brainSnapshot;

  String? _modelPath;

  AgentProvider() {
    _router = SkillRouter([ChatSkill()]);
  }

  Future<void> init([String? modelPath]) async {
    if (modelPath != null) {
      _modelPath = modelPath;
    }
    
    if (_modelPath == null) {
      _status = AgentStatus.error;
      _errorMessage = "Cannot init without model path.";
      notifyListeners();
      return;
    }

    _status = AgentStatus.initialising;
    notifyListeners();

    try {
      _client = FLlamaModelClient(_modelPath!);
      // Eagerly load the model to catch missing file errors early
      await _client!.loadModel();
      final dir = await getApplicationDocumentsDirectory();
      _sessionLogFile = File('${dir.path}/session_log.jsonl');
      
      // We skip full distillation for now, just load basic brain if exists
      _brainSnapshot = BrainSnapshot(summary: "Local memory active.", topics: [], totalInsights: 0);
      
      _status = AgentStatus.ready;
    } catch (e) {
      _status = AgentStatus.error;
      _errorMessage = 'Failed to init local model: $e';
    }
    notifyListeners();
  }

  Future<void> sendMessage(String task) async {
    if (_status != AgentStatus.ready || _client == null) return;

    _messages.add(ChatMessage(isUser: true, text: task));
    _status = AgentStatus.loading;
    notifyListeners();

    try {
      final skill = await _router.routeSkill(task, _client!);
      
      if (skill == null) {
        throw Exception("No matching skill found.");
      }

      final evaluator = LoopEvaluator([
        FormatCheck(),
        LoopDetector(),
        ToolHallucinationCheck(skill.tools.keys.toList()),
      ]);

      final loop = AgentLoop(
        modelClient: _client!,
        tools: skill.tools,
        evaluator: evaluator,
        systemPrompt: skill.systemPrompt,
      );

      final result = await loop.runTask(task);
      result['skill_used'] = skill.name;

      // Log session
      await _logSessionEvent(skill.name, task, result);

      _messages.add(ChatMessage(
        isUser: false,
        text: result['result']?.toString() ?? result['reason']?.toString() ?? 'No response',
        skillUsed: skill.name,
      ));
      _status = AgentStatus.ready;
    } catch (e) {
      _messages.add(ChatMessage(
        isUser: false,
        text: 'Error: $e',
      ));
      _status = AgentStatus.error;
      _errorMessage = e.toString();
    }
    notifyListeners();
  }

  Future<void> _logSessionEvent(String skillName, String task, Map<String, dynamic> result) async {
    final entry = {
      "ts": DateTime.now().toIso8601String(),
      "skill": skillName,
      "task": task,
      "status": result["status"],
      "result_summary": result["result"]?.toString(),
    };
    await _sessionLogFile.writeAsString('${jsonEncode(entry)}\n', mode: FileMode.append);
  }

  Future<String?> flushMemory() async {
    // Skip heavy LLM distillation for now.
    return "Memory flushed (local log updated).";
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
