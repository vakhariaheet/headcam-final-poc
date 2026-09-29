import 'package:flutter/material.dart';

import 'fakes/fake_stream_hat.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile/models/hat_device.dart';
import 'package:mobile/screens/live_broadcast_screen.dart';
import 'package:mobile/services/cloud_control_api_client.dart';
import 'package:mobile/services/user_session_store.dart';
import 'package:mobile/state/broadcast_session_provider.dart';
import 'package:mobile/state/hat_connection_provider.dart';
import 'package:mobile/state/user_auth_provider.dart';

/// A single fixed telemetry sample — this screen only needs its
/// telemetry-dependent UI to leave its loading state, not any particular
/// values. The real service's stream never emits against hardware that
/// doesn't push telemetry over BLE yet (see real_hat_connection_service.dart),
/// which would otherwise leave a spinner animating forever and pumpAndSettle
/// never settling.
Stream<HatTelemetry> _fixedTelemetry(Ref ref) => Stream.value(
  const HatTelemetry(
    batteryLevelPct: 90,
    socTemperatureC: 40,
    outboundBitrateKbps: 2200,
    fps: 30,
  ),
);

/// See preflight_check_screen_test.dart for why this subclasses
/// UserSessionStore directly rather than faking flutter_secure_storage.
class _FakeSessionStore extends UserSessionStore {
  @override
  Future<String?> readToken() async => 'tok_1';
}

/// Builds a container already in a live session (goLive() called for
/// real, against a stubbed CloudControlApiClient), the state this screen
/// is normally only ever reached in.
Future<ProviderContainer> _liveContainer(http.Client cloudClient) async {
  final container = ProviderContainer(
    overrides: [
      hatConnectionServiceProvider.overrideWithValue(FakeStreamHat()),
      userSessionStoreProvider.overrideWithValue(_FakeSessionStore()),
      cloudControlApiClientProvider.overrideWithValue(
        CloudControlApiClient(client: cloudClient, baseUrl: 'http://test'),
      ),
      hatTelemetryProvider.overrideWith(_fixedTelemetry),
    ],
  );
  await container.read(broadcastSessionProvider.notifier).goLive();
  return container;
}

/// Both the once-a-second elapsed ticker and cloudStatusProvider's poll
/// always have a next tick scheduled as long as something's running —
/// disposing explicitly here (rather than relying on addTearDown, which
/// runs after the framework's own "no pending timers" check, or on
/// testWidgets' implicit end-of-test teardown) cancels them while the
/// test body still controls pumping.
Future<void> _disposeCleanly(
  WidgetTester tester,
  ProviderContainer container,
) async {
  await tester.pumpWidget(const SizedBox());
  container.dispose();
  await tester.pump();
}

void main() {
  testWidgets('shows the cloud status pill reflecting a live session', (
    tester,
  ) async {
    final cloudClient = MockClient((request) async {
      if (request.url.path.endsWith('/status')) {
        return http.Response('{"sessionId":"s1","status":"LIVE"}', 200);
      }
      return http.Response('{"sessionId":"s1","status":"LIVE"}', 201);
    });
    final container = await _liveContainer(cloudClient);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: LiveBroadcastScreen()),
      ),
    );
    // cloudStatusProvider polls every 2s — advance past the first tick.
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();

    expect(find.text('Cloud: LIVE'), findsOneWidget);
    await _disposeCleanly(tester, container);
  });

  testWidgets(
    'Kill Switch flips to not-live immediately even when the cloud stop call fails, and surfaces the failure',
    (tester) async {
      final cloudClient = MockClient((request) async {
        if (request.method == 'POST' && request.url.path.endsWith('/stop')) {
          return http.Response(
            '{"error":{"code":"INTERNAL_ERROR","message":"Could not reach the worker"}}',
            500,
          );
        }
        if (request.url.path.endsWith('/status')) {
          return http.Response('{"sessionId":"s1","status":"LIVE"}', 200);
        }
        return http.Response('{"sessionId":"s1","status":"LIVE"}', 201);
      });
      final container = await _liveContainer(cloudClient);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: LiveBroadcastScreen()),
        ),
      );
      await tester.pump();
      expect(find.byKey(const Key('liveDot')), findsOneWidget);

      final endBroadcastButton = find.text('End Broadcast');
      await tester.ensureVisible(endBroadcastButton);
      await tester.tap(endBroadcastButton);
      // The local flip happens synchronously, before endBroadcast()'s first
      // await — no pump duration needed to observe it.
      await tester.pump();
      expect(find.byKey(const Key('liveDot')), findsNothing);

      // The background stop call now fails; let it settle and the
      // SnackBar appear.
      await tester.pumpAndSettle();
      expect(find.text('Could not reach the worker'), findsOneWidget);
      await _disposeCleanly(tester, container);
    },
  );

  testWidgets(
    'a status poll reporting FAILED flips to not-live and shows an error, without Kill Switch',
    (tester) async {
      final cloudClient = MockClient((request) async {
        if (request.url.path.endsWith('/status')) {
          return http.Response('{"sessionId":"s1","status":"FAILED"}', 200);
        }
        return http.Response('{"sessionId":"s1","status":"LIVE"}', 201);
      });
      final container = await _liveContainer(cloudClient);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: LiveBroadcastScreen()),
        ),
      );
      await tester.pump();
      expect(find.byKey(const Key('liveDot')), findsOneWidget);

      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('liveDot')), findsNothing);
      expect(find.text('Broadcast ended unexpectedly.'), findsOneWidget);
      await _disposeCleanly(tester, container);
    },
  );
}
