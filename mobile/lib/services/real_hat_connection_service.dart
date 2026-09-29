import 'dart:async';
import 'dart:convert';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../models/hat_device.dart';
import 'hat_connection_service.dart';

final _provisioningServiceUuid = Guid('FFE0');
final _credentialsCharUuid = Guid('FFE1');
final _statusCharUuid = Guid('FFE2');
const _advertisedNamePrefix = 'UmpireHat_';

/// `flutter_blue_plus`-backed [HatConnectionService] talking to the GATT
/// service `firmware/amb82_hat_native` advertises (spec §4.2/§4.3):
/// service 0xFFE0, write characteristic 0xFFE1 (credentials in), notify
/// characteristic 0xFFE2 (status out). See the native firmware README for the
/// exact wire protocol both sides agree on — notably, `session_token` is
/// deliberately omitted from the FFE1 payload (unlike the spec's example):
/// the AmebaPro2 BLE stack hard-caps a characteristic's buffer at 230
/// bytes, and a real session JWT alone runs longer than that. Re-add it
/// once a chunked-write protocol exists on both sides.
class RealHatConnectionService implements HatConnectionService {
  BluetoothDevice? _device;
  BluetoothCharacteristic? _credentialsChar;
  BluetoothCharacteristic? _statusChar;
  int _streamOperation = 0;
  void Function()? _cancelStreamWait;

  @override
  Future<bool> requestBluetoothAccess() async {
    final state = await FlutterBluePlus.adapterState
        .firstWhere((s) => s != BluetoothAdapterState.unknown)
        .timeout(
          const Duration(seconds: 5),
          onTimeout: () => BluetoothAdapterState.unknown,
        );
    return state == BluetoothAdapterState.on;
  }

  @override
  Stream<HatDevice> scan() async* {
    final controller = StreamController<List<ScanResult>>();
    final subscription = FlutterBluePlus.scanResults.listen(controller.add);

    // Not filtering by withServices here: the firmware puts the FFE0
    // service UUID in the scan response packet, not the primary
    // advertisement, and iOS CoreBluetooth's withServices filter is
    // unreliable against scan-response-only service UUIDs. Filtering by
    // the advertised name instead - the Master Spec's own description of
    // this screen ("scanning for UmpireHat_XXXX advertisements") - since
    // the name is in the primary packet and always present.
    const scanDuration = Duration(seconds: 8);
    await FlutterBluePlus.startScan(timeout: scanDuration);

    // FlutterBluePlus.scanResults only emits when a new advertisement
    // arrives - it never pushes a final event just because scanning
    // internally stopped. Relying on that to end the `await for` below
    // would hang forever once no further devices are found, even after
    // the timeout above elapses. Closing the controller ourselves on a
    // matching timer makes the stream end for real.
    final deadline = Timer(
      scanDuration + const Duration(milliseconds: 500),
      () {
        if (!controller.isClosed) controller.close();
      },
    );

    final seen = <String>{};
    try {
      await for (final results in controller.stream) {
        for (final result in results) {
          final name = result.advertisementData.advName.isNotEmpty
              ? result.advertisementData.advName
              : result.device.platformName;
          if (!name.startsWith(_advertisedNamePrefix)) continue;

          final id = result.device.remoteId.str;
          if (seen.add(id)) {
            yield HatDevice(id: id, name: name, rssi: result.rssi);
          }
        }
      }
    } finally {
      deadline.cancel();
      await subscription.cancel();
      if (!controller.isClosed) await controller.close();
      if (FlutterBluePlus.isScanningNow) await FlutterBluePlus.stopScan();
    }
  }

  @override
  Future<void> connect(String deviceId) async {
    final device = BluetoothDevice.fromId(deviceId);
    await device.connect();

    final services = await device.discoverServices();
    final service = services.firstWhere(
      (s) => s.uuid == _provisioningServiceUuid,
    );
    _credentialsChar = service.characteristics.firstWhere(
      (c) => c.uuid == _credentialsCharUuid,
    );
    _statusChar = service.characteristics.firstWhere(
      (c) => c.uuid == _statusCharUuid,
    );
    _device = device;
  }

  @override
  Future<void> provisionHotspot({
    required String ssid,
    required String passphrase,
    required String band,
  }) async {
    final credentialsChar = _credentialsChar;
    final statusChar = _statusChar;
    if (credentialsChar == null || statusChar == null) {
      throw StateError('provisionHotspot called before connect()');
    }

    final payload = jsonEncode({
      'cmd': 'SET_STA',
      'ssid': ssid,
      'pass': passphrase,
      'band': band,
    });

    await statusChar.setNotifyValue(true);
    // FFE2 now also carries stream events. Listen for a fresh provisioning
    // result; cached values or publishing notifications cannot complete pairing.
    final result = Completer<Map<String, dynamic>>();
    void finish(Map<String, dynamic> value) {
      if (!result.isCompleted) result.complete(value);
    }

    final subscription = statusChar.onValueReceived.listen(
      (bytes) {
        try {
          final value = jsonDecode(utf8.decode(bytes));
          if (value is Map<String, dynamic> &&
              value['event'] == null &&
              (value['status'] == 'connected' || value['status'] == 'error')) {
            finish(value);
          }
        } on FormatException {
          /* Ignore unrelated or malformed notifications. */
        }
      },
      onError: (Object error) =>
          finish({'status': 'error', 'reason': 'ble_disconnected'}),
    );
    // Association, SDK DHCP, and camera startup have separate deadlines.
    final timer = Timer(
      const Duration(seconds: 120),
      () => finish({'status': 'error', 'reason': 'provisioning_timeout'}),
    );
    try {
      await credentialsChar.write(
        utf8.encode(payload),
        withoutResponse: false,
        allowLongWrite: true,
      );
      final response = await result.future;
      if (response['status'] != 'connected') {
        throw HatProvisioningError(
          response['reason'] as String? ?? 'unknown_error',
        );
      }
    } finally {
      timer.cancel();
      await subscription.cancel();
    }
  }

  @override
  Future<void> startStream({String? ingestUrl}) async {
    final operation = ++_streamOperation;
    try {
      await _streamCommand(
        {'cmd': 'START_STREAM', 'url': ?ingestUrl},
        'publishing',
        operation,
      );
    } catch (_) {
      // Do not leave retrying firmware behind after an unsuccessful start.
      if (operation == _streamOperation) {
        try {
          await stopStream();
        } catch (_) {
          throw StateError(
            'Stream start failed and stop could not be confirmed. '
            'Reconnect to the hat or power it off to stop publishing.',
          );
        }
      }
      rethrow;
    }
  }

  @override
  Future<void> stopStream() =>
      _streamCommand({'cmd': 'STOP_STREAM'}, 'stopped', ++_streamOperation);

  Future<void> _streamCommand(
    Map<String, String> command,
    String expected,
    int operation,
  ) async {
    _cancelStreamWait?.call();
    final credentials = _credentialsChar;
    final status = _statusChar;
    if (credentials == null || status == null) {
      throw StateError('Connect to the hat before controlling its stream.');
    }
    await status.setNotifyValue(true);
    if (operation != _streamOperation) {
      throw StateError('Stream command cancelled.');
    }
    final result = Completer<String>();
    void finish(String value) {
      if (!result.isCompleted) result.complete(value);
    }

    void cancel() => finish('cancelled');
    _cancelStreamWait = cancel;
    final subscription = status.onValueReceived.listen((bytes) {
      try {
        final value = jsonDecode(utf8.decode(bytes));
        if (value is Map && value['event'] == 'stream') {
          if (value['status'] == expected) finish('ok');
          if (value['status'] == 'error') finish('error');
        }
      } on FormatException {
        /* Ignore unrelated or malformed notifications. */
      }
    }, onError: (Object error) => finish('disconnected'));
    final timer = Timer(const Duration(seconds: 20), () => finish('timeout'));
    try {
      final payload = utf8.encode(jsonEncode(command));
      if (payload.length >= 512) {
        throw StateError('Stream destination is too long.');
      }
      await credentials.write(
        payload,
        withoutResponse: false,
        allowLongWrite: true,
      );
      final outcome = await result.future;
      if (outcome != 'ok' || operation != _streamOperation) {
        throw StateError('Hat stream command failed: $outcome.');
      }
    } finally {
      timer.cancel();
      await subscription.cancel();
      if (identical(_cancelStreamWait, cancel)) _cancelStreamWait = null;
    }
  }

  @override
  Stream<HatTelemetry> telemetryStream() {
    // amb82_hat_native doesn't push periodic telemetry over BLE yet (see
    // its README's "known limitations") - only the one-time status message
    // provisionHotspot already consumes. Returning an empty stream is
    // deliberate, not a placeholder bug: the Live screen won't show
    // numbers against real hardware until that firmware piece exists.
    return const Stream.empty();
  }

  @override
  Future<void> disconnect() async {
    _streamOperation++;
    _cancelStreamWait?.call();
    await _device?.disconnect();
    _device = null;
    _credentialsChar = null;
    _statusChar = null;
  }
}

/// Thrown by [RealHatConnectionService.provisionHotspot] when the board
/// reports `{"status":"error",...}` on characteristic 0xFFE2.
class HatProvisioningError implements Exception {
  const HatProvisioningError(this.reason);
  final String reason;

  @override
  String toString() => 'Hat provisioning failed: $reason';
}
