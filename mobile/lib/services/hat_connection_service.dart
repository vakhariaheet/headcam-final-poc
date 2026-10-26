import '../models/hat_device.dart';
import '../models/hat_status.dart';

/// BLE pairing/provisioning/telemetry surface for the hat (spec §4, §6.2
/// Screens 2/3/6). Backed by `RealHatConnectionService`
/// (`flutter_blue_plus`) against the GATT service
/// `firmware/amb82_hat_native` advertises — see the native firmware README for
/// the wire protocol.
abstract class HatConnectionService {
  /// Requests the platform Bluetooth permission needed for discovery.
  /// Returns false when access is declined or unavailable.
  Future<bool> requestBluetoothAccess();

  /// Scans for nearby `UmpireHat_XXXX` BLE advertisements.
  Stream<HatDevice> scan();

  /// Connects to [deviceId]. Spec §6.2 calls for an 8-second handshake
  /// timeout with auto-retry; implementations should throw
  /// [HatConnectionTimeout] if that window elapses.
  Future<void> connect(String deviceId);

  /// Claims the connected hat while it is in pairing mode, replacing any
  /// previous owner. Returns the new owner key (hex) to store securely.
  /// Throws [HatOwnershipError] when pairing mode is closed.
  Future<String> claim();

  /// Proves ownership of the connected hat with [ownerKey]. Every command
  /// other than [claim] requires this first. Throws [HatOwnershipError] when
  /// the key is wrong or the hat has no owner.
  Future<void> authenticate(String ownerKey);

  /// Pushes hotspot credentials over the provisioning characteristic
  /// (spec §4.3, service 0xFFE0 / characteristic 0xFFE1).
  Future<void> provisionHotspot({
    required String ssid,
    required String passphrase,
    required String band,
  });

  /// Start outbound publishing. A null URL uses the firmware's configured URL.
  Future<void> startStream({String? ingestUrl});

  /// Stop publishing and cancel connection retries without disconnecting Wi-Fi.
  Future<void> stopStream();

  /// Live telemetry once connected (spec §7.2 `telemetry_samples`).
  Stream<HatTelemetry> telemetryStream();

  /// Reads the authenticated hat's identity, firmware version, and camera
  /// health.
  Future<HatInfo> readInfo();

  /// Camera failures as they happen. The hat restarts itself up to
  /// [HatCameraFault.maxRestarts] times, which drops the BLE link.
  Stream<HatCameraFault> cameraFaults();

  /// Asks the hat to download and install [release] over its own Wi-Fi.
  /// Completes once the hat has started; follow [updateEvents] for
  /// progress. Throws [HatUpdateError] when the hat refuses.
  Future<void> updateFirmware(FirmwareRelease release);

  /// Firmware update progress notifications.
  Stream<HatUpdateEvent> updateEvents();

  Future<void> disconnect();
}

/// The hat rejected a claim or ownership proof. [reason] is the firmware's
/// code: `pairing_closed`, `not_owner`, `no_owner`, `no_challenge`,
/// `bad_request`, `key_store_failed`, `challenge_failed`, or `timeout`.
class HatOwnershipError implements Exception {
  const HatOwnershipError(this.reason);
  final String reason;

  @override
  String toString() => 'Hat ownership check failed: $reason';
}

class HatConnectionTimeout implements Exception {
  const HatConnectionTimeout(this.deviceId);
  final String deviceId;

  @override
  String toString() => 'Timed out connecting to $deviceId';
}

/// The hat refused or failed a firmware update. [reason] is the firmware's
/// code, e.g. `no_wifi`, `streaming`, `busy`, or `bad_url`.
class HatUpdateError implements Exception {
  const HatUpdateError(this.reason);
  final String reason;

  @override
  String toString() => 'Hat firmware update failed: $reason';
}
