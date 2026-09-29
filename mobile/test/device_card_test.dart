import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/models/hat_device.dart';
import 'package:mobile/state/hat_connection_provider.dart';
import 'package:mobile/widgets/device_card.dart';

void main() {
  Widget wrap(Widget child, {List<Override> overrides = const []}) =>
      ProviderScope(
        overrides: overrides,
        child: MaterialApp(home: Scaffold(body: child)),
      );

  DeviceCard buildCard() => DeviceCard(
    onStartBroadcast: () {},
    onPairNewHat: () {},
    onChooseExistingHat: () {},
  );

  testWidgets('unpaired, no known hats: only Pair New Hat is offered', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(buildCard()));
    await tester.pump();

    expect(find.text('Not connected'), findsOneWidget);
    expect(find.text('Pair New Hat'), findsOneWidget);
    expect(find.text('Choose Existing Hat'), findsNothing);
  });

  testWidgets(
    'unpaired, with a known hat: both Pair New Hat and Choose Existing Hat show',
    (tester) async {
      await tester.pumpWidget(
        wrap(
          buildCard(),
          overrides: [
            pairedHatIdsProvider.overrideWith((ref) async => ['hat-7f3a']),
          ],
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('Pair New Hat'), findsOneWidget);
      expect(find.text('Choose Existing Hat'), findsOneWidget);
    },
  );

  testWidgets(
    'connected: shows telemetry and Start Broadcast, not the pairing prompt',
    (tester) async {
      final notifier = _ConnectedNotifier();
      await tester.pumpWidget(
        wrap(
          buildCard(),
          overrides: [hatConnectionProvider.overrideWith(() => notifier)],
        ),
      );
      await tester.pump();

      expect(find.text('Connected'), findsOneWidget);
      expect(find.text('Start Broadcast'), findsOneWidget);
      expect(find.text('Pair New Hat'), findsNothing);
    },
  );
}

class _ConnectedNotifier extends HatConnectionNotifier {
  @override
  HatConnectionState build() => const HatConnectionState(
    status: HatConnectionStatus.connected,
    connectedDevice: HatDevice(
      id: 'hat-7f3a',
      name: 'UmpireHat_7F3A',
      rssi: -52,
    ),
  );
}
