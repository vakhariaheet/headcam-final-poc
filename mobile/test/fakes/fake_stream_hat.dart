import 'package:mobile/models/hat_device.dart';
import 'package:mobile/models/hat_status.dart';
import 'package:mobile/services/hat_connection_service.dart';

class FakeStreamHat implements HatConnectionService {
  final calls = <String>[];
  bool failStart = false;
  bool failStop = false;
  @override
  Future<void> startStream({String? ingestUrl}) async {
    calls.add('start');
    if (failStart) throw StateError('ingest unavailable');
  }

  @override
  Future<void> stopStream() async {
    calls.add('stop');
    if (failStop) throw StateError('BLE unavailable');
  }

  @override
  Future<bool> requestBluetoothAccess() async => true;
  @override
  Stream<HatDevice> scan() => const Stream.empty();
  @override
  Future<void> connect(String deviceId) async {}
  @override
  Future<String> claim() async => 'fake-owner-key';
  @override
  Future<void> authenticate(String ownerKey) async {}
  @override
  Future<void> disconnect() async {}
  @override
  Future<void> provisionHotspot({
    required String ssid,
    required String passphrase,
    required String band,
  }) async {}
  @override
  Stream<HatTelemetry> telemetryStream() => const Stream.empty();
  @override
  Future<HatInfo> readInfo() async => const HatInfo(
    serialNumber: '00E04C000001',
    hardwareModel: 'AMB82_MINI_V1',
    firmwareVersion: '0.2.0',
  );
  @override
  Stream<HatCameraFault> cameraFaults() => const Stream.empty();
  @override
  Future<void> updateFirmware(FirmwareRelease release) async {}
  @override
  Stream<HatUpdateEvent> updateEvents() => const Stream.empty();
}
