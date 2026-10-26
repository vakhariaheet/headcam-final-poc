import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../models/hat_device.dart';
import '../models/hat_status.dart';
import 'hat_connection_service.dart';
import 'hat_ownership_protocol.dart';

final _provisioningServiceUuid = Guid('FFE0');
final _credentialsCharUuid = Guid('FFE1');
final _statusCharUuid = Guid('FFE2');
final _statusServiceGuid = Guid(hatStatusServiceUuid);
const _advertisedNamePrefix = 'UmpireHat_';

/// `flutter_blue_plus`-backed [HatConnectionService] talking to the GATT
/// service `firmware/amb82_hat_native` advertises (spec §4.2/§4.3):
/// service 0xFFE0, write characteristic 0xFFE1 (credentials in), notify
/// characteristic 0xFFE2 (status out). See the native firmware README for the
/// exact wire protocol both sides agree on. Every command except `CLAIM`
/// needs a link authenticated with [authenticate]; the hat rejects others
/// with ATT application error 0x81.
class RealHatConnectionService implements HatConnectionService {
  BluetoothDevice? _device;
  BluetoothCharacteristic? _credentialsChar;
  BluetoothCharacteristic? _statusChar;
  Uint8List? _sessionKey;
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
            final flags = HatAdvertisementFlags.fromServiceData(
              result.advertisementData.serviceData[_statusServiceGuid],
            );
            yield HatDevice(
              id: id,
              name: name,
              rssi: result.rssi,
              pairingMode: flags.pairingMode,
              owned: flags.owned,
            );
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
    _sessionKey = null; // a new link must authenticate again
  }

  @override
  Future<String> claim() async {
    final keyPair = HatClaimKeyPair.generate();
    final reply = await _exchange({
      'cmd': 'CLAIM',
      'pub': base64.encode(keyPair.publicKey),
    }, (value) => value['event'] == 'claim');
    final hatPublic = reply['pub'];
    if (reply['status'] != 'ok' || hatPublic is! String) {
      throw HatOwnershipError(reply['reason'] as String? ?? 'unknown_error');
    }
    try {
      return hexEncode(keyPair.deriveOwnerKey(base64.decode(hatPublic)));
    } on Object {
      throw const HatOwnershipError('bad_hat_key');
    }
  }

  @override
  Future<void> authenticate(String ownerKey) async {
    final challenge = await _exchange({
      'cmd': 'AUTH_START',
    }, (value) => value['event'] == 'auth');
    final nonce = challenge['nonce'];
    if (nonce is! String) {
      throw HatOwnershipError(
        challenge['reason'] as String? ?? 'unknown_error',
      );
    }
    final result = await _exchange({
      'cmd': 'AUTH',
      'mac': hatOwnerProof(ownerKeyHex: ownerKey, nonceHex: nonce),
    }, (value) => value['event'] == 'auth' && value['nonce'] == null);
    if (result['status'] != 'ok') {
      throw HatOwnershipError(result['reason'] as String? ?? 'unknown_error');
    }
    _sessionKey = hatSessionKey(ownerKeyHex: ownerKey, nonceHex: nonce);
  }

  /// Seals [params] under this link's session key; see [authenticate].
  String _seal(String command, Map<String, Object?> params) {
    final key = _sessionKey;
    if (key == null) {
      throw StateError('Authenticate with the hat before sending $command.');
    }
    return hatSeal(sessionKey: key, command: command, params: params);
  }

  /// Writes [command] and returns the first FFE2 notification [isReply]
  /// accepts. Listening starts before the write so a fast reply is not missed.
  Future<Map<String, dynamic>> _exchange(
    Map<String, Object?> command,
    bool Function(Map<String, dynamic> value) isReply,
  ) async {
    final commandChar = _credentialsChar;
    final status = _statusChar;
    if (commandChar == null || status == null) {
      throw StateError('Connect to the hat first.');
    }
    await status.setNotifyValue(true);
    final reply = Completer<Map<String, dynamic>>();
    final subscription = status.onValueReceived.listen(
      (bytes) {
        try {
          final value = jsonDecode(utf8.decode(bytes));
          if (value is Map<String, dynamic> &&
              isReply(value) &&
              !reply.isCompleted) {
            reply.complete(value);
          }
        } on FormatException {
          /* Ignore unrelated or malformed notifications. */
        }
      },
      onError: (Object error) {
        if (!reply.isCompleted) {
          reply.completeError(const HatOwnershipError('ble_disconnected'));
        }
      },
    );
    try {
      await commandChar.write(
        hatCommand(command),
        withoutResponse: false,
        allowLongWrite: true,
      );
      return await reply.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw const HatOwnershipError('timeout'),
      );
    } finally {
      await subscription.cancel();
    }
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

    // Credentials only ever cross the air sealed with the session key.
    final payload = jsonEncode({
      'cmd': 'SET_STA',
      'sealed': _seal('SET_STA', {
        'ssid': ssid,
        'pass': passphrase,
        'band': band,
      }),
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
      // An ingest URL may embed a stream key, so it is sealed.
      await _streamCommand(
        {
          'cmd': 'START_STREAM',
          if (ingestUrl != null)
            'sealed': _seal('START_STREAM', {'url': ingestUrl}),
        },
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
    Map<String, Object?> command,
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

  /// Every JSON object the hat notifies on FFE2 while this link lasts.
  /// Status, stream, telemetry, camera, and update events share it.
  Stream<Map<String, dynamic>> _notifications() async* {
    final status = _statusChar;
    if (status == null) return;
    await status.setNotifyValue(true);
    await for (final bytes in status.onValueReceived) {
      try {
        final value = jsonDecode(utf8.decode(bytes));
        if (value is Map<String, dynamic>) yield value;
      } on FormatException {
        /* Ignore malformed notifications. */
      }
    }
  }

  @override
  Stream<HatTelemetry> telemetryStream() => _notifications()
      .map(HatTelemetry.fromNotification)
      .where((sample) => sample != null)
      .cast<HatTelemetry>();

  @override
  Future<HatInfo> readInfo() async {
    final reply = await _exchange({
      'cmd': 'INFO',
    }, (value) => value['event'] == 'info');
    final info = HatInfo.fromNotification(reply);
    if (info == null) throw const FormatException('Malformed hat INFO reply');
    return info;
  }

  @override
  Stream<HatCameraFault> cameraFaults() => _notifications()
      .map(HatCameraFault.fromNotification)
      .where((fault) => fault != null)
      .cast<HatCameraFault>();

  @override
  Future<void> updateFirmware(FirmwareRelease release) async {
    // The hash is what lets the hat trust an image fetched over plain
    // HTTP, so it only travels sealed.
    final Map<String, dynamic> reply;
    try {
      reply = await _exchange({
        'cmd': 'UPDATE_FW',
        'sealed': _seal('UPDATE_FW', {
          'url': release.downloadUrl,
          'size': release.sizeBytes,
          'sha256': release.sha256,
          'version': release.version,
        }),
      }, (value) => value['event'] == 'ota');
    } on HatOwnershipError catch (e) {
      throw HatUpdateError(e.reason); // timeout or a dropped link
    }
    final event = HatUpdateEvent.fromNotification(reply);
    if (event is HatUpdateFailed) throw HatUpdateError(event.reason);
    if (event is! HatUpdateStarted) throw const HatUpdateError('no_reply');
  }

  @override
  Stream<HatUpdateEvent> updateEvents() => _notifications()
      .map(HatUpdateEvent.fromNotification)
      .where((event) => event != null)
      .cast<HatUpdateEvent>();

  @override
  Future<void> disconnect() async {
    _streamOperation++;
    _cancelStreamWait?.call();
    await _device?.disconnect();
    _device = null;
    _credentialsChar = null;
    _statusChar = null;
    _sessionKey = null;
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
