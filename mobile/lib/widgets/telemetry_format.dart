/// Display strings for optional hat telemetry. Real hardware reports neither
/// battery nor temperature, so absent values render as a dash rather than
/// a made-up number.
String formatBatteryLevel(int? percent) => percent == null ? '—' : '$percent%';

String formatTemperature(double? celsius) =>
    celsius == null ? '—' : '${celsius.toStringAsFixed(0)}°C';
