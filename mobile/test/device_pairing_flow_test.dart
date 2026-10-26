import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/models/hat_device.dart';
import 'package:mobile/models/hat_status.dart';
import 'package:mobile/screens/device_discovery_screen.dart';
import 'package:mobile/services/hat_connection_service.dart';
import 'package:mobile/state/hat_connection_provider.dart';
import 'package:mobile/theme/app_theme.dart';

import 'fakes/memory_owner_key_store.dart';

/// Scripted stand-in for the real BLE service, timed to match this test's
/// pumped durations — see real_hat_connection_service.dart for what this
/// replaces against actual hardware.
class _FakeHatConnectionService implements HatConnectionService {
  @override
  Future<void> startStream({String? ingestUrl}) async {}
  @override
  Future<void> stopStream() async {}

  @override
  Future<bool> requestBluetoothAccess() async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    return true;
  }

  @override
  Stream<HatDevice> scan() async* {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    yield const HatDevice(
      id: 'hat-7f3a',
      name: 'UmpireHat_7F3A',
      rssi: -52,
      pairingMode: true,
    );
    await Future<void>.delayed(const Duration(milliseconds: 600));
    yield const HatDevice(id: 'hat-c19e', name: 'UmpireHat_C19E', rssi: -71);
  }

  @override
  Future<void> connect(String deviceId) async {
    await Future<void>.delayed(const Duration(milliseconds: 450));
  }

  @override
  Future<String> claim() async => 'fake-owner-key';

  @override
  Future<void> authenticate(String ownerKey) async {}

  @override
  Future<void> provisionHotspot({
    required String ssid,
    required String passphrase,
    required String band,
  }) async {
    await Future<void>.delayed(const Duration(seconds: 1));
  }

  @override
  Stream<HatTelemetry> telemetryStream() => const Stream.empty();

  @override
  Future<HatInfo> readInfo() async => const HatInfo(
    serialNumber: '00E04C007F3A',
    hardwareModel: 'AMB82_MINI_V1',
    firmwareVersion: '0.2.0',
  );
  @override
  Stream<HatCameraFault> cameraFaults() => const Stream.empty();
  @override
  Future<void> updateFirmware(FirmwareRelease release) async {}
  @override
  Stream<HatUpdateEvent> updateEvents() => const Stream.empty();

  @override
  Future<void> disconnect() async {}
}

void main() {
  testWidgets('pairs a discovered hat and offers Wi-Fi setup', (tester) async {
    final keyStore = MemoryOwnerKeyStore();
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          hatConnectionServiceProvider.overrideWithValue(
            _FakeHatConnectionService(),
          ),
          hatOwnerKeyStoreProvider.overrideWithValue(keyStore),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const DeviceDiscoveryScreen(),
          routes: {
            '/home': (_) => const Scaffold(body: Text('Home')),
            '/hotspot': (_) => const Scaffold(body: Text('Wi-Fi setup')),
          },
        ),
      ),
    );

    expect(find.text('Set up your UmpireHat'), findsOneWidget);
    expect(find.text('Add Device'), findsOneWidget);

    await tester.tap(find.text('Add Device'));
    await tester.pumpAndSettle();
    expect(find.text('Enable Bluetooth'), findsOneWidget);

    await tester.tap(find.text('Allow Bluetooth'));
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('Searching for devices'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Select your device'), findsOneWidget);
    expect(find.text('UmpireHat_7F3A'), findsOneWidget);

    final connectButton = find.byKey(const Key('pairingConnectButton'));
    final connectAction = tester.widget<FilledButton>(connectButton).onPressed;
    expect(connectAction, isNotNull);
    await tester.ensureVisible(connectButton);
    await tester.pumpAndSettle();
    connectAction!();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Connecting...'), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Device paired!'), findsOneWidget);
    expect(find.text('Next: Wi-Fi Setup'), findsOneWidget);
    expect(
      keyStore.keys['hat-7f3a'],
      'fake-owner-key',
    ); // claimed in pairing mode

    await tester.tap(find.text('Next: Wi-Fi Setup'));
    await tester.pumpAndSettle();
    expect(find.text('Wi-Fi setup'), findsOneWidget);
  });
}
