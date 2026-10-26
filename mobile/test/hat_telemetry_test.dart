import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/models/hat_device.dart';
import 'package:mobile/widgets/telemetry_format.dart';

void main() {
  group('HatTelemetry.fromNotification', () {
    test('parses a firmware telemetry sample', () {
      final sample = HatTelemetry.fromNotification({
        'event': 'telemetry',
        'kbps': 2010,
        'tx_kbps': 1980,
        'fps': 30,
        'rssi': -54,
        'stream': 'publishing',
      });

      expect(sample, isNotNull);
      expect(sample!.outboundBitrateKbps, 1980);
      expect(sample.encoderBitrateKbps, 2010);
      expect(sample.fps, 30.0);
      expect(sample.wifiRssiDbm, -54);
      expect(sample.streamState, 'publishing');
      expect(sample.batteryLevelPct, isNull);
      expect(sample.socTemperatureC, isNull);
    });

    test('accepts a null RSSI while Wi-Fi is down', () {
      final sample = HatTelemetry.fromNotification({
        'event': 'telemetry',
        'kbps': 0,
        'tx_kbps': 0,
        'fps': 0,
        'rssi': null,
        'stream': 'reconnecting',
      });

      expect(sample?.wifiRssiDbm, isNull);
    });

    test('ignores status, stream, and malformed messages', () {
      expect(
        HatTelemetry.fromNotification({
          'status': 'connected',
          'ip': '192.0.2.1',
        }),
        isNull,
      );
      expect(
        HatTelemetry.fromNotification({
          'event': 'stream',
          'status': 'publishing',
        }),
        isNull,
      );
      expect(
        HatTelemetry.fromNotification({'event': 'telemetry', 'kbps': '2010'}),
        isNull,
      );
    });
  });

  test('absent battery and temperature render as a dash', () {
    expect(formatBatteryLevel(null), '—');
    expect(formatTemperature(null), '—');
    expect(formatBatteryLevel(90), '90%');
    expect(formatTemperature(40.4), '40°C');
  });
}
