import 'package:flutter/material.dart';
import 'package:mobile/state/hat_connection_provider.dart';

import 'fakes/fake_stream_hat.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile/screens/preflight_check_screen.dart';
import 'package:mobile/services/cloud_control_api_client.dart';
import 'package:mobile/services/user_session_store.dart';
import 'package:mobile/state/broadcast_session_provider.dart';
import 'package:mobile/state/shell_navigation_provider.dart';
import 'package:mobile/state/user_auth_provider.dart';

/// A real signed-in session, without touching the secure-storage plugin's
/// platform channel — UserSessionStore has no abstract interface, but its
/// methods aren't sealed/final either, so overriding just [readToken] is
/// simpler and more robust than faking flutter_secure_storage internals.
class _FakeSessionStore extends UserSessionStore {
  @override
  Future<String?> readToken() async => 'tok_1';
}

void main() {
  Widget wrap(Widget child, http.Client cloudClient) => ProviderScope(
    overrides: [
      hatConnectionServiceProvider.overrideWithValue(FakeStreamHat()),
      userSessionStoreProvider.overrideWithValue(_FakeSessionStore()),
      cloudControlApiClientProvider.overrideWithValue(
        CloudControlApiClient(client: cloudClient, baseUrl: 'http://test'),
      ),
    ],
    child: MaterialApp(
      initialRoute: '/home',
      routes: {
        '/home': (_) => const Scaffold(body: Text('Home Screen')),
        '/preflight': (_) => child,
      },
    ),
  );

  testWidgets(
    'Start Broadcast selects the Live tab and pops back when goLive succeeds',
    (tester) async {
      final cloudClient = MockClient((request) async {
        return http.Response('{"sessionId":"s1","status":"LIVE"}', 201);
      });

      await tester.pumpWidget(wrap(const PreflightCheckScreen(), cloudClient));
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.pushNamed('/preflight');
      await tester.pumpAndSettle();

      // The pre-flight check passes once the mock uplink timer ticks at
      // least once (>=300ms) — tilt starts at a passing default (0°) since
      // no real accelerometer exists in this test environment.
      await tester.pump(const Duration(milliseconds: 350));

      await tester.tap(find.text('Start Broadcast'));
      await tester.pumpAndSettle();

      final context = tester.element(find.byType(Navigator));
      expect(
        ProviderScope.containerOf(context).read(selectedShellTabProvider),
        ShellTab.live,
      );
      expect(find.text('Home Screen'), findsOneWidget);
    },
  );

  testWidgets(
    'Start Broadcast shows an error and stays on Preflight when goLive fails',
    (tester) async {
      final cloudClient = MockClient((request) async {
        return http.Response(
          '{"error":{"code":"AT_CAPACITY","message":"This worker instance is at capacity"}}',
          503,
        );
      });

      await tester.pumpWidget(wrap(const PreflightCheckScreen(), cloudClient));
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.pushNamed('/preflight');
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 350));

      await tester.tap(find.text('Start Broadcast'));
      await tester.pumpAndSettle();

      expect(find.text('This worker instance is at capacity'), findsOneWidget);
      expect(find.text('Pre-Flight Check'), findsOneWidget);

      // Dispose explicitly (rather than relying on testWidgets' implicit
      // teardown) and drain the resulting microtask — PreflightNotifier.stop()
      // defers its state write by one, so a pending-timer check right at
      // test end would otherwise catch it mid-flight.
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );
}
