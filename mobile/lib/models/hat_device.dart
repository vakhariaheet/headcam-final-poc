/// A discovered UmpireHat edge node, as advertised over BLE (spec §4.2, §6.2
/// Screen 2). Populated by [HatConnectionService.scan].
class HatDevice {
  const HatDevice({required this.id, required this.name, required this.rssi});

  final String id;
  final String name;

  final int rssi;
}

/// Live telemetry sample streamed from a connected hat (spec §7.2
/// `telemetry_samples`, §6.2 Screen 6).
class HatTelemetry {
  const HatTelemetry({
    required this.batteryLevelPct,
    required this.socTemperatureC,
    required this.outboundBitrateKbps,
    required this.fps,
  });

  final int batteryLevelPct;
  final double socTemperatureC;
  final int outboundBitrateKbps;
  final double fps;
}
