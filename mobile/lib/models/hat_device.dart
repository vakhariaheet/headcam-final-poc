/// A discovered UmpireHat edge node, as advertised over BLE (spec §4.2, §6.2
/// Screen 2). Populated by [HatConnectionService.scan].
class HatDevice {
  const HatDevice({
    required this.id,
    required this.name,
    required this.rssi,
    this.pairingMode = false,
    this.owned = false,
  });

  final String id;
  final String name;

  final int rssi;

  /// The hat's button opened its pairing window, so a new phone may claim it.
  final bool pairingMode;

  /// Some phone already holds this hat's owner key (maybe this one).
  final bool owned;
}

/// Live telemetry sample streamed from a connected hat (spec §7.2
/// `telemetry_samples`, §6.2 Screen 6).
///
/// The AMB82 hat has no battery gauge or temperature sensor, so
/// [batteryLevelPct] and [socTemperatureC] are null for real hardware
/// rather than fabricated. [wifiRssiDbm] is null while Wi-Fi is down.
class HatTelemetry {
  const HatTelemetry({
    required this.outboundBitrateKbps,
    required this.fps,
    this.encoderBitrateKbps,
    this.wifiRssiDbm,
    this.streamState,
    this.batteryLevelPct,
    this.socTemperatureC,
  });

  /// Parses an FFE2 `{"event":"telemetry",...}` notification, or returns
  /// null when [json] is not a well-formed telemetry sample.
  static HatTelemetry? fromNotification(Map<String, dynamic> json) {
    if (json['event'] != 'telemetry') return null;
    final encoderKbps = json['kbps'];
    final sentKbps = json['tx_kbps'];
    final fps = json['fps'];
    final rssi = json['rssi'];
    final stream = json['stream'];
    if (encoderKbps is! int || sentKbps is! int || fps is! num) return null;
    return HatTelemetry(
      outboundBitrateKbps: sentKbps,
      encoderBitrateKbps: encoderKbps,
      fps: fps.toDouble(),
      wifiRssiDbm: rssi is int ? rssi : null,
      streamState: stream is String ? stream : null,
    );
  }

  /// Bitrate actually handed to the RTMP connection; zero when not publishing.
  final int outboundBitrateKbps;
  final double fps;
  final int? encoderBitrateKbps;
  final int? wifiRssiDbm;

  /// Publisher state: `idle`, `connecting`, `publishing`, `reconnecting`, or `stopped`.
  final String? streamState;
  final int? batteryLevelPct;
  final double? socTemperatureC;
}
