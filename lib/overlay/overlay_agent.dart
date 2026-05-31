import 'package:flutter/foundation.dart';

import '../agent/gemma_client.dart';
import '../agent/harness/harness.dart';
import '../agent/model_config.dart';

class OverlayMsg {
  final bool fromUser;
  final String text;
  final String? thinking;
  OverlayMsg(this.fromUser, this.text, {this.thinking});
}

class OverlayAgent extends ChangeNotifier {
  GemmaModelClient? _client;
  WranglHarness? _harness;

  Uint8List? pendingImage;
  bool loading = false;
  bool booting = false;
  bool ready = false;
  String? error;
  String? lastThink;
  final List<OverlayMsg> messages = [];

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
    messages.add(OverlayMsg(true, text));
    loading = true;
    notifyListeners();
    lastThink = null;
    try {
      final reply = await _harness!.handle(
        text,
        image: image,
        priorTurns: prior,
        onStep: (_) {
          notifyListeners();
        },
      );
      messages.add(OverlayMsg(false, reply, thinking: lastThink));
    } catch (e) {
      messages.add(OverlayMsg(false, 'Error: $e'));
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
