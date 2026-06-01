import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wranglv0/agent/harness/harness.dart';
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

  test('resetSession cancels an in-flight turn and clears loading', () {
    final agent = OverlayAgent();
    final token = CancellationToken();
    agent.cancelTokenForTest = token;
    agent.loading = true;
    agent.messages.add(OverlayMsg(true, 'in flight'));
    expect(token.isCancelled, isFalse);

    agent.resetSession();

    expect(token.isCancelled, isTrue);
    expect(agent.loading, isFalse,
        reason:
            'resetSession must clear loading so the next send is not blocked by an orphaned turn');
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

  test('resetSession during in-flight send drops the late reply', () async {
    final completer = Completer<String>();
    Future<String> fakeModel({
      required String system,
      required List<Map<String, dynamic>> history,
      Uint8List? image,
      int maxTokens = 512,
    }) =>
        completer.future;
    final harness = WranglHarness.load(fakeModel);
    final agent = OverlayAgent();
    agent.harnessForTest = harness;

    final sendFuture = agent.send('hello');
    // Yield so send() can populate messages + enter the await
    await Future<void>.delayed(Duration.zero);
    expect(agent.messages.length, 1);
    expect(agent.loading, isTrue);

    agent.resetSession();
    expect(agent.messages, isEmpty);
    expect(agent.loading, isFalse,
        reason: 'next send should be allowed after reset');

    // The model eventually finishes — but the reply is for the old session.
    completer.complete('late reply');
    await sendFuture;

    expect(agent.messages, isEmpty,
        reason: 'late reply must not be added to the new session');
    expect(agent.sessionId, 1);
  });
}

