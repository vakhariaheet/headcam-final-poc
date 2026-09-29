import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/broadcast_session_provider.dart';
import '../state/hat_connection_provider.dart';
import '../state/match_provider.dart';
import '../state/shell_navigation_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/destructive_button.dart';
import '../widgets/metric_column.dart';
import '../widgets/status_pill.dart';

String _signalLabel(int? rssi) {
  if (rssi == null) return '—';
  if (rssi >= -60) return 'Excellent';
  if (rssi >= -75) return 'Good';
  return 'Weak';
}

/// Screen 6: Live Broadcast Console (spec §6.2) — reached by landing on
/// [AppShell]'s Live tab once a broadcast starts (see
/// preflight_check_screen.dart), not a standalone pushed route.
///
/// [LiveBroadcastScreen] is a thin `Scaffold` wrapper kept only for direct
/// widget-testing convenience; it isn't registered as a named route.
class LiveBroadcastScreen extends StatelessWidget {
  const LiveBroadcastScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: SafeArea(child: LiveBroadcastView()));
  }
}

/// The real console body, built to design.md §13's layout: LIVE + timer
/// header, "Streaming from" the connected hat, a camera preview placeholder (no real
/// video feed in this POC — same honest mocked-but-real-shaped treatment
/// as the rest of the hardware layer), the battery/temperature/signal
/// grid, an optional Score Overlay status block, End Broadcast, and
/// Device|Settings quick links back into the shell. Battery/temperature/
/// bitrate/fps come from the mock telemetry stream ([hatTelemetryProvider])
/// standing in for real BLE telemetry ticks until hardware exists.
class LiveBroadcastView extends ConsumerWidget {
  const LiveBroadcastView({super.key});

  String _formatDuration(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final hours = two(d.inHours);
    final minutes = two(d.inMinutes.remainder(60));
    final seconds = two(d.inSeconds.remainder(60));
    return '$hours:$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(broadcastSessionProvider);
    final telemetry = ref.watch(hatTelemetryProvider);
    final cloudStatus = ref.watch(cloudStatusProvider);
    final device = ref.watch(hatConnectionProvider).connectedDevice;
    final match = ref.watch(matchSetupProvider).matchInfo;

    ref.listen(broadcastSessionProvider, (previous, next) {
      if (next.error != null && next.error != previous?.error) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(next.error!)));
      }
    });

    // See BroadcastSessionNotifier.reportEndedUnexpectedly for why this
    // reconciliation lives here rather than inside that notifier's own
    // build() (a genuine circular-dependency constraint, not a style
    // choice).
    ref.listen(cloudStatusProvider, (_, next) {
      final status = next.valueOrNull;
      if (status != null && !status.isLive) {
        ref.read(broadcastSessionProvider.notifier).reportEndedUnexpectedly();
      }
    });

    return SingleChildScrollView(
      padding: AppSpacing.screenPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (session.isLive)
                Row(
                  children: [
                    const Icon(
                      Icons.circle,
                      key: Key('liveDot'),
                      color: AppColors.live,
                      size: 12,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'LIVE',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: AppColors.live,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                )
              else
                const SizedBox.shrink(),
              Text(
                _formatDuration(session.elapsed),
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Streaming from ${device?.name ?? 'UmpireHat'}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.md),
          telemetry.when(
            data: (t) =>
                _CameraPreview(fps: t.fps, bitrateKbps: t.outboundBitrateKbps),
            loading: () => const _CameraPreview(fps: null, bitrateKbps: null),
            error: (_, _) => const _CameraPreview(fps: null, bitrateKbps: null),
          ),
          const SizedBox(height: AppSpacing.lg),
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
                    value: _signalLabel(device?.rssi),
                    label: 'Signal',
                  ),
                ),
              ],
            ),
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            ),
            error: (err, _) => Text('Telemetry error: $err'),
          ),
          const SizedBox(height: AppSpacing.md),
          cloudStatus.when(
            data: (status) => Align(
              alignment: Alignment.centerLeft,
              child: StatusPill(
                label: 'Cloud: ${status.status}',
                kind: status.isLive ? StatusKind.live : StatusKind.offline,
              ),
            ),
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const Align(
              alignment: Alignment.centerLeft,
              child: StatusPill(
                label: 'Cloud: unreachable',
                kind: StatusKind.offline,
              ),
            ),
          ),
          if (match != null) ...[
            const SizedBox(height: AppSpacing.md),
            const _ScoreOverlayStatus(),
          ],
          const SizedBox(height: AppSpacing.lg),
          DestructiveButton(
            icon: Icons.stop_circle_outlined,
            label: 'End Broadcast',
            onPressed: session.isLive
                ? () =>
                      ref.read(broadcastSessionProvider.notifier).endBroadcast()
                : null,
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton(
                onPressed: () => ref
                    .read(selectedShellTabProvider.notifier)
                    .select(ShellTab.devices),
                child: const Text('Device'),
              ),
              const Text(
                '  |  ',
                style: TextStyle(color: AppColors.textSecondary),
              ),
              TextButton(
                onPressed: () => ref
                    .read(selectedShellTabProvider.notifier)
                    .select(ShellTab.settings),
                child: const Text('Settings'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CameraPreview extends StatelessWidget {
  const _CameraPreview({required this.fps, required this.bitrateKbps});

  final double? fps;
  final int? bitrateKbps;

  @override
  Widget build(BuildContext context) {
    final stats = fps != null && bitrateKbps != null
        ? '1080p · ${fps!.toStringAsFixed(0)} FPS    '
              '${(bitrateKbps! / 1000).toStringAsFixed(1)} Mbps'
        : null;

    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.navySurface,
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: Stack(
          children: [
            const Center(
              child: Icon(
                Icons.videocam_outlined,
                color: AppColors.navyTextSecondary,
                size: 40,
              ),
            ),
            const Positioned(
              top: 12,
              right: 12,
              child: StatusPill(label: 'LIVE', kind: StatusKind.live),
            ),
            if (stats != null)
              Positioned(
                left: 12,
                bottom: 12,
                child: Text(
                  stats,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ScoreOverlayStatus extends StatelessWidget {
  const _ScoreOverlayStatus();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Score Overlay',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Source: External integration',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const StatusPill(label: 'Synced', kind: StatusKind.connected),
          ],
        ),
      ),
    );
  }
}
