import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile/services/cloud_control_api_client.dart';
import 'package:mobile/services/user_session_store.dart';
import 'package:mobile/state/broadcast_session_provider.dart';
import 'package:mobile/state/hat_connection_provider.dart';
import 'package:mobile/state/user_auth_provider.dart';

import 'fakes/fake_stream_hat.dart';

class SessionStore extends UserSessionStore {
  @override
  Future<String?> readToken() async => 'test-token';
}

void main() {
  ProviderContainer setup(
    FakeStreamHat hat,
    Future<http.Response> Function(http.Request) handler,
  ) {
    final container = ProviderContainer(
      overrides: [
        hatConnectionServiceProvider.overrideWithValue(hat),
        userSessionStoreProvider.overrideWithValue(SessionStore()),
        cloudControlApiClientProvider.overrideWithValue(
          CloudControlApiClient(
            client: MockClient(handler),
            baseUrl: 'http://test',
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('unexpected cloud termination stops the publisher', () async {
    final hat = FakeStreamHat();
    final c = setup(hat, (r) async => http.Response('{"sessionId":"s1"}', 201));
    final n = c.read(broadcastSessionProvider.notifier);
    expect(await n.goLive(), true);
    n.reportEndedUnexpectedly();
    await Future<void>.delayed(Duration.zero);
    expect(hat.calls, ['start', 'stop']);
    expect(c.read(broadcastSessionProvider).isLive, false);
  });
  test('publisher failure prevents cloud session and stops retries', () async {
    final hat = FakeStreamHat()..failStart = true;
    var requests = 0;
    final c = setup(hat, (r) async {
      requests++;
      return http.Response('{}', 500);
    });
    expect(await c.read(broadcastSessionProvider.notifier).goLive(), false);
    expect(requests, 0);
    expect(hat.calls, ['start', 'stop']);
    expect(c.read(broadcastSessionProvider).isLive, false);
  });
  test('cloud start failure rolls back outbound publisher', () async {
    final hat = FakeStreamHat();
    final c = setup(
      hat,
      (r) async => http.Response('{"error":{"message":"offline"}}', 503),
    );
    expect(await c.read(broadcastSessionProvider.notifier).goLive(), false);
    expect(hat.calls, ['start', 'stop']);
  });
  test('stop attempts cloud cleanup even when BLE stop fails', () async {
    final hat = FakeStreamHat();
    final requests = <String>[];
    final c = setup(hat, (r) async {
      requests.add(r.url.path);
      return http.Response(
        '{"sessionId":"s1"}',
        r.url.path.endsWith('/stop') ? 200 : 201,
      );
    });
    final n = c.read(broadcastSessionProvider.notifier);
    expect(await n.goLive(), true);
    hat.failStop = true;
    await n.endBroadcast();
    expect(requests, ['/sessions', '/sessions/s1/stop']);
    expect(c.read(broadcastSessionProvider).isLive, false);
    expect(c.read(broadcastSessionProvider).error, contains('hat stopped'));
  });
  test('stop while cloud start is pending cleans up late session', () async {
    final hat = FakeStreamHat();
    final pending = Completer<http.Response>();
    final requested = Completer<void>();
    final stopped = <String>[];
    final c = setup(hat, (r) async {
      if (r.url.path == '/sessions') {
        requested.complete();
        return pending.future;
      }
      stopped.add(r.url.path);
      return http.Response('{}', 200);
    });
    final n = c.read(broadcastSessionProvider.notifier);
    final start = n.goLive();
    await requested.future;
    await n.endBroadcast();
    pending.complete(http.Response('{"sessionId":"late"}', 201));
    expect(await start, false);
    expect(stopped, ['/sessions/late/stop']);
    expect(hat.calls, ['start', 'stop']);
    expect(c.read(broadcastSessionProvider).isLive, false);
  });
}
