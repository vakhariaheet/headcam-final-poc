import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile/models/hat_device.dart';
import 'package:mobile/models/hat_status.dart';
import 'package:mobile/services/device_api_client.dart';
import 'package:mobile/services/hat_connection_service.dart';
import 'package:mobile/services/user_session_store.dart';
import 'package:mobile/state/firmware_update_provider.dart';
import 'package:mobile/state/hat_connection_provider.dart';
import 'package:mobile/state/user_auth_provider.dart';
import 'package:mobile/widgets/firmware_update_card.dart';
import 'package:mobile/widgets/hat_connection_messages.dart';
import 'package:mobile/widgets/hat_health_banner.dart';

import 'fakes/memory_owner_key_store.dart';

/// Owned hat whose INFO, camera faults, and update events are scripted.
class _ScriptedHat implements HatConnectionService {
  _ScriptedHat({HatInfo? info}) : info = info ?? _info();

  HatInfo info;
  Object? infoError;
  String? refuseUpdate;
  final updates = <FirmwareRelease>[];
  final faults = StreamController<HatCameraFault>.broadcast();
  final events = StreamController<HatUpdateEvent>.broadcast();

  @override
  Future<HatInfo> readInfo() async {
    if (infoError != null) throw infoError!;
    return info;
  }

  @override
  Stream<HatCameraFault> cameraFaults() => faults.stream;

  @override
  Future<void> updateFirmware(FirmwareRelease release) async {
    updates.add(release);
    if (refuseUpdate != null) throw HatUpdateError(refuseUpdate!);
  }

  @override
  Stream<HatUpdateEvent> updateEvents() => events.stream;

  @override
  Future<void> connect(String deviceId) async {}
  @override
  Future<void> authenticate(String ownerKey) async {}
  @override
  Future<String> claim() async => 'owner-key';
  @override
  Future<void> disconnect() async {}
  @override
  Future<bool> requestBluetoothAccess() async => true;
  @override
  Stream<HatDevice> scan() => const Stream.empty();
  @override
  Future<void> provisionHotspot({
    required String ssid,
    required String passphrase,
    required String band,
  }) async {}
  @override
  Future<void> startStream({String? ingestUrl}) async {}
  @override
  Future<void> stopStream() async {}
  @override
  Stream<HatTelemetry> telemetryStream() => const Stream.empty();
}

HatInfo _info({
  String firmware = '0.2.0',
  HatCameraHealth camera = HatCameraHealth.ok,
  int restarts = 0,
}) => HatInfo(
  serialNumber: '00E04C0A1B2C',
  hardwareModel: 'AMB82_MINI_V1',
  firmwareVersion: firmware,
  camera: camera,
  cameraRestarts: restarts,
);

class _TokenStore extends UserSessionStore {
  _TokenStore(this.token);
  final String? token;
  @override
  Future<String?> readToken() async => token;
}

/// Backend double recording what the app sent.
class _Backend {
  final requests = <http.Request>[];
  Map<String, dynamic>? latest = {
    'version': '0.3.0',
    'sha256': 'ab' * 32,
    'sizeBytes': 3096580,
    'downloadUrl': 'http://192.168.1.20:4000/api/v1/firmware-releases/x/image',
    'notes': null,
  };
  bool down = false;

  DeviceApiClient client() => DeviceApiClient(
    baseUrl: 'http://backend.test',
    client: MockClient((request) async {
      requests.add(request);
      if (down) return http.Response('{"error":{"message":"down"}}', 503);
      if (request.method == 'PUT') return http.Response('{}', 201);
      return http.Response(
        jsonEncode({
          'items': [?latest],
        }),
        200,
      );
    }),
  );
}

const _hat = HatDevice(id: 'ble-1', name: 'UmpireHat_1B2C', rssi: -50);

Future<ProviderContainer> _connected(
  _ScriptedHat hat,
  _Backend backend, {
  String? token = 'session-token',
}) async {
  final keys = MemoryOwnerKeyStore()..keys[_hat.id] = 'owner-key';
  final container = ProviderContainer(
    overrides: [
      hatConnectionServiceProvider.overrideWithValue(hat),
      hatOwnerKeyStoreProvider.overrideWithValue(keys),
      deviceApiClientProvider.overrideWithValue(backend.client()),
      userSessionStoreProvider.overrideWithValue(_TokenStore(token)),
    ],
  );
  addTearDown(container.dispose);
  await container.read(hatConnectionProvider.notifier).connect(_hat);
  await pumpEventQueue();
  return container;
}

void main() {
  group('firmware notifications', () {
    // Exactly as the firmware's snprintf formats print them.
    test('INFO replies parse', () {
      final info = HatInfo.fromNotification(
        jsonDecode(
          '{"event":"info","id":"00E04C0A1B2C","model":"AMB82_MINI_V1",'
          '"fw":"0.2.0","camera":"recovered","camera_restarts":2,'
          '"camera_max":3}',
        ) as Map<String, dynamic>,
      )!;
      expect(info.serialNumber, '00E04C0A1B2C');
      expect(info.hardwareModel, 'AMB82_MINI_V1');
      expect(info.firmwareVersion, '0.2.0');
      expect(info.camera, HatCameraHealth.recovered);
      expect(info.cameraRestarts, 2);
      expect(info.cameraMaxRestarts, 3);

      expect(
        HatInfo.fromNotification({
          'event': 'info',
          'id': 'X',
          'model': 'M',
          'fw': '1',
          'camera': 'failed',
        })!.camera,
        HatCameraHealth.failed,
      );
      expect(HatInfo.fromNotification({'event': 'info', 'id': 'X'}), isNull);
      expect(HatInfo.fromNotification({'event': 'telemetry'}), isNull);
    });

    test('camera faults parse', () {
      final restarting = HatCameraFault.fromNotification(
        jsonDecode(
          '{"event":"camera_fault","reason":"video_stalled",'
          '"action":"restarting","restarts":1,"max":3}',
        ) as Map<String, dynamic>,
      )!;
      expect(restarting.restarting, isTrue);
      expect(restarting.reason, 'video_stalled');
      expect(restarting.restarts, 1);
      final stopped = HatCameraFault.fromNotification({
        'event': 'camera_fault',
        'reason': 'video_no_frames',
        'action': 'stopped',
        'restarts': 3,
        'max': 3,
      })!;
      expect(stopped.restarting, isFalse);
      expect(
        HatCameraFault.fromNotification({
          'event': 'camera_fault',
          'reason': 'x',
          'action': 'exploded',
          'restarts': 1,
          'max': 3,
        }),
        isNull,
      );
    });

    test('update events parse', () {
      HatUpdateEvent? parse(String json) => HatUpdateEvent.fromNotification(
        jsonDecode(json) as Map<String, dynamic>,
      );
      expect(
        parse('{"event":"ota","status":"started"}'),
        isA<HatUpdateStarted>(),
      );
      expect(
        (parse('{"event":"ota","status":"downloading","progress":40}')!
                as HatUpdateDownloading)
            .percent,
        40,
      );
      expect(
        (parse('{"event":"ota","status":"rebooting","version":"0.3.0"}')!
                as HatUpdateRebooting)
            .version,
        '0.3.0',
      );
      expect(
        (parse('{"event":"ota","status":"error","reason":"hash_mismatch"}')!
                as HatUpdateFailed)
            .reason,
        'hash_mismatch',
      );
      expect(parse('{"event":"ota","status":"downloading"}'), isNull);
      expect(parse('{"event":"stream","status":"publishing"}'), isNull);
    });

    test('firmware versions order numerically', () {
      expect(compareFirmwareVersions('0.10.0', '0.9.2'), greaterThan(0));
      expect(compareFirmwareVersions('0.3.0', '0.3'), 0);
      expect(compareFirmwareVersions('1.0.0-rc1', '1.0.0'), lessThan(0));
      expect(compareFirmwareVersions('0.2.0', '0.3.0'), lessThan(0));
      expect(compareFirmwareVersions('0.3.0', '0.3.0'), 0);
      expect(compareFirmwareVersions('1.0.0+build7', '1.0.0'), 0);
      expect(compareFirmwareVersions('1.0.0-rc2', '1.0.0-rc1'), greaterThan(0));
    });
  });

  group('camera messages', () {
    test('describe restarts, giving up, and recovery', () {
      const restarting = HatCameraFault(
        reason: 'video_stalled',
        restarting: true,
        restarts: 2,
        maxRestarts: 3,
      );
      expect(hatCameraMessage(fault: restarting), contains('attempt 2 of 3'));
      expect(hatCameraNeedsPowerCycle(fault: restarting), isFalse);

      const stopped = HatCameraFault(
        reason: 'video_stalled',
        restarting: false,
        restarts: 3,
        maxRestarts: 3,
      );
      expect(hatCameraMessage(fault: stopped), contains('off and on again'));
      expect(hatCameraNeedsPowerCycle(fault: stopped), isTrue);

      final failed = _info(camera: HatCameraHealth.failed, restarts: 3);
      expect(hatCameraMessage(info: failed), contains('off and on again'));
      expect(hatCameraNeedsPowerCycle(info: failed), isTrue);
      expect(
        hatCameraMessage(
          info: _info(camera: HatCameraHealth.recovered, restarts: 1),
        ),
        contains('restarted once'),
      );
      expect(
        hatCameraMessage(
          info: _info(camera: HatCameraHealth.recovered, restarts: 2),
        ),
        contains('restarted 2 times'),
      );
      expect(hatCameraMessage(info: _info()), isNull);
      expect(hatCameraMessage(), isNull);
      // A live fault outranks older health.
      expect(
        hatCameraMessage(fault: restarting, info: failed),
        contains('attempt 2 of 3'),
      );
    });
  });

  group('connecting', () {
    test('reads INFO and links the hat to the signed-in account', () async {
      final backend = _Backend();
      final container = await _connected(_ScriptedHat(), backend);

      final state = container.read(hatConnectionProvider);
      expect(state.status, HatConnectionStatus.connected);
      expect(state.info?.serialNumber, '00E04C0A1B2C');
      final link = backend.requests.single;
      expect(link.method, 'PUT');
      expect(link.url.path, '/api/v1/devices/00E04C0A1B2C');
      expect(link.headers['Authorization'], 'Bearer session-token');
      expect(jsonDecode(link.body), {
        'hardwareModel': 'AMB82_MINI_V1',
        'firmwareVersion': '0.2.0',
        'cameraRestarts': 0,
        'cameraFailed': false,
      });
    });

    test('reports camera health to the backend', () async {
      final backend = _Backend();
      await _connected(
        _ScriptedHat(info: _info(camera: HatCameraHealth.failed, restarts: 3)),
        backend,
      );
      expect(
        jsonDecode(backend.requests.single.body),
        containsPair('cameraFailed', true),
      );
    });

    test('a backend outage does not affect the BLE connection', () async {
      final backend = _Backend()..down = true;
      final container = await _connected(_ScriptedHat(), backend);
      expect(
        container.read(hatConnectionProvider).status,
        HatConnectionStatus.connected,
      );
      expect(container.read(hatConnectionProvider).info, isNotNull);
    });

    test('signed out: connects without linking', () async {
      final backend = _Backend();
      await _connected(_ScriptedHat(), backend, token: null);
      expect(backend.requests, isEmpty);
    });

    test('older firmware without INFO still connects', () async {
      final backend = _Backend();
      final hat = _ScriptedHat()..infoError = StateError('write rejected');
      final container = await _connected(hat, backend);
      expect(
        container.read(hatConnectionProvider).status,
        HatConnectionStatus.connected,
      );
      expect(container.read(hatConnectionProvider).info, isNull);
      expect(backend.requests, isEmpty);
    });
  });

  group('firmware updates', () {
    test('finds a newer release and installs it', () async {
      final hat = _ScriptedHat();
      final backend = _Backend();
      final container = await _connected(hat, backend);
      final notifier = container.read(firmwareUpdateProvider.notifier);

      await notifier.check();
      var update = container.read(firmwareUpdateProvider);
      expect(update.phase, FirmwareUpdatePhase.available);
      expect(update.release?.version, '0.3.0');
      final query = backend.requests.last.url;
      expect(query.path, '/api/v1/firmware-releases');
      expect(query.queryParameters, {
        'hardwareModel': 'AMB82_MINI_V1',
        'limit': '1',
      });

      await notifier.install();
      expect(hat.updates.single.sha256, 'ab' * 32);
      expect(
        container.read(firmwareUpdateProvider).phase,
        FirmwareUpdatePhase.installing,
      );

      hat.events.add(const HatUpdateDownloading(40));
      await pumpEventQueue();
      update = container.read(firmwareUpdateProvider);
      expect(update.percent, 40);

      hat.events.add(const HatUpdateRebooting('0.3.0'));
      await pumpEventQueue();
      expect(
        container.read(firmwareUpdateProvider).phase,
        FirmwareUpdatePhase.rebooting,
      );
    });

    test('up to date when the hat already runs the latest', () async {
      final backend = _Backend();
      final container = await _connected(
        _ScriptedHat(info: _info(firmware: '0.3.0')),
        backend,
      );
      await container.read(firmwareUpdateProvider.notifier).check();
      expect(
        container.read(firmwareUpdateProvider).phase,
        FirmwareUpdatePhase.upToDate,
      );
    });

    test('up to date when nothing is published', () async {
      final backend = _Backend()..latest = null;
      final container = await _connected(_ScriptedHat(), backend);
      await container.read(firmwareUpdateProvider.notifier).check();
      expect(
        container.read(firmwareUpdateProvider).phase,
        FirmwareUpdatePhase.upToDate,
      );
    });

    test('the hat refusing an update is reported', () async {
      final hat = _ScriptedHat()..refuseUpdate = 'streaming';
      final container = await _connected(hat, _Backend());
      final notifier = container.read(firmwareUpdateProvider.notifier);
      await notifier.check();
      await notifier.install();
      final update = container.read(firmwareUpdateProvider);
      expect(update.phase, FirmwareUpdatePhase.failed);
      expect(update.failure, 'streaming');
      expect(
        hatUpdateFailureMessage(update.failure!),
        'Stop the broadcast before updating your UmpireHat.',
      );
    });

    test('a failed download is reported', () async {
      final hat = _ScriptedHat();
      final container = await _connected(hat, _Backend());
      final notifier = container.read(firmwareUpdateProvider.notifier);
      await notifier.check();
      await notifier.install();
      hat.events.add(const HatUpdateFailed('hash_mismatch'));
      await pumpEventQueue();
      final update = container.read(firmwareUpdateProvider);
      expect(update.phase, FirmwareUpdatePhase.failed);
      expect(
        hatUpdateFailureMessage(update.failure!),
        contains('did not match'),
      );
    });

    test('silence during an install fails it', () {
      fakeAsync((async) {
        final hat = _ScriptedHat();
        late ProviderContainer container;
        _connected(hat, _Backend()).then((c) => container = c);
        async.elapse(const Duration(seconds: 1)); // connect + pumpEventQueue
        final notifier = container.read(firmwareUpdateProvider.notifier);
        notifier.check();
        async.elapse(Duration.zero);
        notifier.install();
        async.elapse(Duration.zero);

        async.elapse(const Duration(seconds: 50));
        hat.events.add(const HatUpdateDownloading(10)); // progress resets it
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 50));
        expect(
          container.read(firmwareUpdateProvider).phase,
          FirmwareUpdatePhase.installing,
        );
        async.elapse(const Duration(seconds: 11));
        expect(container.read(firmwareUpdateProvider).failure, 'no_progress');
      });
    });

    test('check fails cleanly when signed out or offline', () async {
      final signedOut = await _connected(
        _ScriptedHat(),
        _Backend(),
        token: null,
      );
      await signedOut.read(firmwareUpdateProvider.notifier).check();
      expect(signedOut.read(firmwareUpdateProvider).failure, 'signed_out');

      final backend = _Backend();
      final offline = await _connected(_ScriptedHat(), backend);
      backend.down = true;
      await offline.read(firmwareUpdateProvider.notifier).check();
      expect(offline.read(firmwareUpdateProvider).failure, 'check_failed');
    });
  });

  group('widgets', () {
    Future<_ScriptedHat> pumpCard(WidgetTester tester, {HatInfo? info}) async {
      final hat = _ScriptedHat(info: info);
      final keys = MemoryOwnerKeyStore()..keys[_hat.id] = 'owner-key';
      final backend = _Backend();
      final container = ProviderContainer(
        overrides: [
          hatConnectionServiceProvider.overrideWithValue(hat),
          hatOwnerKeyStoreProvider.overrideWithValue(keys),
          deviceApiClientProvider.overrideWithValue(backend.client()),
          userSessionStoreProvider.overrideWithValue(_TokenStore('t')),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          // Default theme: the app theme fetches Google Fonts over the network.
          child: MaterialApp(
            home: const Scaffold(
              body: Column(children: [HatHealthBanner(), FirmwareUpdateCard()]),
            ),
          ),
        ),
      );
      await tester.runAsync(
        () => container.read(hatConnectionProvider.notifier).connect(_hat),
      );
      await tester.pumpAndSettle();
      return hat;
    }

    testWidgets('healthy hat: no banner; update offered and installed', (
      tester,
    ) async {
      final hat = await pumpCard(tester);
      expect(find.byKey(const Key('hatHealthBanner')), findsNothing);
      expect(find.text('0.2.0'), findsOneWidget);

      await tester.tap(find.text('Check for updates'));
      await tester.runAsync(() => pumpEventQueue());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Update to 0.3.0'));
      await tester.pump();
      hat.events.add(const HatUpdateDownloading(60));
      await tester.pump();
      await tester.pump();
      expect(find.text('Installing 0.3.0… 60%'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      hat.events.add(const HatUpdateRebooting('0.3.0'));
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('restarting with 0.3.0'), findsOneWidget);
    });

    testWidgets('a hat that gave up on its camera says to power-cycle it', (
      tester,
    ) async {
      await pumpCard(
        tester,
        info: _info(camera: HatCameraHealth.failed, restarts: 3),
      );
      expect(find.byKey(const Key('hatHealthBanner')), findsOneWidget);
      expect(find.textContaining('off and on again'), findsOneWidget);
    });

    testWidgets('a live camera fault shows the restart attempt', (
      tester,
    ) async {
      final hat = await pumpCard(tester);
      hat.faults.add(
        const HatCameraFault(
          reason: 'video_stalled',
          restarting: true,
          restarts: 1,
          maxRestarts: 3,
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('attempt 1 of 3'), findsOneWidget);
    });
  });
}
