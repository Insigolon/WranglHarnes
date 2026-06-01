import 'package:flutter/foundation.dart';

import '../agent/gemma_client.dart';
import '../agent/harness/harness.dart';
import '../agent/harness/tool.dart';
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

  /// Monotonic id bumped on every [resetSession] so views can key off it.
  int sessionId = 0;

  /// Token passed to the in-flight harness call so [resetSession] can cancel.
  CancellationToken _cancelToken = CancellationToken.none;

  @visibleForTesting
  set cancelTokenForTest(CancellationToken token) => _cancelToken = token;

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
    _cancelToken = CancellationToken();
    final token = _cancelToken;
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
        cancelToken: token,
      );
      if (token.isCancelled) return;
      messages.add(OverlayMsg(false, reply, thinking: lastThink));
    } catch (e) {
      if (token.isCancelled) return;
      messages.add(OverlayMsg(false, 'Error: $e'));
    } finally {
      if (identical(_cancelToken, token)) {
        loading = false;
        notifyListeners();
      }
    }
  }

  /// Cancel any in-flight turn and clear the conversation log. The model
  /// client stays resident — only the session state goes away. A pending
  /// image attached to a future send is also dropped.
  void resetSession() {
    if (loading) _cancelToken.cancel();
    messages.clear();
    pendingImage = null;
    lastThink = null;
    error = null;
    sessionId++;
    notifyListeners();
  }

  @override
  void dispose() {
    _client?.dispose();
    super.dispose();
  }
}
