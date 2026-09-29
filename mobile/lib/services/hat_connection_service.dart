import '../models/hat_device.dart';

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

  Future<void> disconnect();
}

class HatConnectionTimeout implements Exception {
  const HatConnectionTimeout(this.deviceId);
  final String deviceId;

  @override
  String toString() => 'Timed out connecting to $deviceId';
}
