import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/hat_connection_provider.dart';
import '../theme/app_theme.dart';
import 'metric_column.dart';
import 'status_pill.dart';

String _signalLabel(int rssi) {
  if (rssi >= -60) return 'Excellent';
  if (rssi >= -75) return 'Good';
  return 'Weak';
}

/// The UmpireHat device card (design.md §12). Reused by both Home and the
/// Devices tab. Branches on whether a hat is connected this session:
/// connected shows live telemetry + Start Broadcast; not connected offers
/// pairing a new hat or choosing one already paired (see
/// pairedHatIdsProvider — "existing" only ever means currently reachable).
class DeviceCard extends ConsumerWidget {
  const DeviceCard({
    super.key,
    required this.onStartBroadcast,
    required this.onPairNewHat,
    required this.onChooseExistingHat,
  });

  final VoidCallback onStartBroadcast;
  final VoidCallback onPairNewHat;
  final VoidCallback onChooseExistingHat;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connection = ref.watch(hatConnectionProvider);
    final isConnected =
        connection.status == HatConnectionStatus.connected ||
        connection.status == HatConnectionStatus.provisioning ||
        connection.status == HatConnectionStatus.provisioned;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: isConnected
            ? _ConnectedContent(onStartBroadcast: onStartBroadcast)
            : _UnpairedContent(
                onPairNewHat: onPairNewHat,
                onChooseExistingHat: onChooseExistingHat,
              ),
      ),
    );
  }
}

class _ConnectedContent extends ConsumerWidget {
  const _ConnectedContent({required this.onStartBroadcast});

  final VoidCallback onStartBroadcast;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connection = ref.watch(hatConnectionProvider);
    final telemetry = ref.watch(hatTelemetryProvider);
    final device = connection.connectedDevice;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                device?.name ?? 'UmpireHat',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const StatusPill(label: 'Connected', kind: StatusKind.connected),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        telemetry.when(
          data: (t) => Row(
            children: [
              Expanded(
                child: MetricColumn(
                  value: '${t.batteryLevelPct}%',
                  label: 'Battery',
                ),
              ),
              Expanded(
                child: MetricColumn(
                  value: '${t.socTemperatureC.toStringAsFixed(0)}°C',
                  label: 'Temperature',
                ),
              ),
              Expanded(
                child: MetricColumn(
                  value: device != null ? _signalLabel(device.rssi) : '—',
                  label: 'Signal',
                ),
              ),
            ],
          ),
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
          error: (_, _) => const SizedBox.shrink(),
        ),
        const SizedBox(height: AppSpacing.md),
        FilledButton(
          onPressed: onStartBroadcast,
          child: const Text('Start Broadcast'),
        ),
      ],
    );
  }
}

class _UnpairedContent extends ConsumerWidget {
  const _UnpairedContent({
    required this.onPairNewHat,
    required this.onChooseExistingHat,
  });

  final VoidCallback onPairNewHat;
  final VoidCallback onChooseExistingHat;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pairedHats = ref.watch(pairedHatIdsProvider).valueOrNull ?? const [];
    final hasPairedHats = pairedHats.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'UmpireHat',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const StatusPill(label: 'Not connected', kind: StatusKind.offline),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          hasPairedHats
              ? 'Choose a paired hat that\'s currently nearby, or pair a new one.'
              : 'Pair your UmpireHat to see live battery, temperature, and '
                    'signal here.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: AppSpacing.md),
        if (hasPairedHats) ...[
          FilledButton(
            onPressed: onChooseExistingHat,
            child: const Text('Choose Existing Hat'),
          ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton(
            onPressed: onPairNewHat,
            child: const Text('Pair New Hat'),
          ),
        ] else
          FilledButton(
            onPressed: onPairNewHat,
            child: const Text('Pair New Hat'),
          ),
      ],
    );
  }
}
