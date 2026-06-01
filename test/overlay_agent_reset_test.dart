import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wranglv0/agent/harness/tool.dart';
import 'package:wranglv0/overlay/overlay_agent.dart';

void main() {
  test('resetSession clears messages, pending image, think, error', () {
    final agent = OverlayAgent();
    agent.messages.add(OverlayMsg(true, 'hello'));
    agent.messages.add(OverlayMsg(false, 'hi back', thinking: 'hmm'));
    agent.pendingImage = Uint8List.fromList([1, 2, 3]);
    agent.lastThink = 'a thought';
    agent.error = 'old error';
    expect(agent.sessionId, 0);

    agent.resetSession();

    expect(agent.messages, isEmpty);
    expect(agent.pendingImage, isNull);
    expect(agent.lastThink, isNull);
    expect(agent.error, isNull);
    expect(agent.sessionId, 1);
  });

  test('resetSession is safe when there is nothing to clear', () {
    final agent = OverlayAgent();
    expect(agent.messages, isEmpty);
    expect(() => agent.resetSession(), returnsNormally);
    expect(agent.sessionId, 1);
  });

  test('resetSession cancels an in-flight turn', () {
    final agent = OverlayAgent();
    final token = CancellationToken();
    agent.cancelTokenForTest = token;
    agent.loading = true;
    agent.messages.add(OverlayMsg(true, 'in flight'));
    expect(token.isCancelled, isFalse);

    agent.resetSession();

    expect(token.isCancelled, isTrue);
    expect(agent.loading, isTrue,
        reason: 'resetSession does not flip loading; the in-flight finally does');
    expect(agent.messages, isEmpty);
    expect(agent.sessionId, 1);
  });

  test('resetSession notifies listeners exactly once per call', () {
    final agent = OverlayAgent();
    agent.messages.add(OverlayMsg(true, 'x'));
    var notifications = 0;
    agent.addListener(() => notifications++);

    agent.resetSession();

    expect(notifications, 1);
  });
}
