import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/models/hat_device.dart';
import 'package:mobile/screens/app_shell.dart';
import 'package:mobile/state/broadcast_session_provider.dart';
import 'package:mobile/state/hat_connection_provider.dart';

/// A fixed live session, without going through goLive()'s real cloud call.
class _LiveNotifier extends BroadcastSessionNotifier {
  @override
  BroadcastSessionState build() => const BroadcastSessionState(isLive: true);
}

/// A single fixed telemetry sample — this test only needs the Live tab's
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

void main() {
  testWidgets('bottom nav switches between all five destinations', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: AppShell())),
    );
    await tester.pump();

    expect(find.text('Recent Recordings'), findsOneWidget);

    await tester.tap(find.text('Devices'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Devices'), findsOneWidget);

    await tester.tap(find.text('Recordings'));
    await tester.pumpAndSettle();
    expect(find.text('No recordings yet'), findsOneWidget);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Sign out'), findsOneWidget);

    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(find.text('Recent Recordings'), findsOneWidget);
  });

  testWidgets('Live tab shows the idle state when not broadcasting', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: AppShell())),
    );
    await tester.pump();

    await tester.tap(find.text('Live'));
    await tester.pumpAndSettle();

    expect(find.text('Not currently broadcasting'), findsOneWidget);
    expect(find.text('End Broadcast'), findsNothing);
  });

  testWidgets('Live tab shows the console when a session is live', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          broadcastSessionProvider.overrideWith(_LiveNotifier.new),
          hatTelemetryProvider.overrideWith(_fixedTelemetry),
        ],
        child: const MaterialApp(home: AppShell()),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Live'));
    await tester.pumpAndSettle();

    expect(find.text('End Broadcast'), findsOneWidget);
  });
}
