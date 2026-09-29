import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/broadcast_session_provider.dart';
import '../state/preflight_provider.dart';
import '../state/shell_navigation_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/status_pill.dart';

/// Screen 5: 3-Second Pre-Flight Check (spec §6.2). Hard-blocks broadcast
/// start on >10° tilt or <2.0 Mbps uplink. Tilt is real (device
/// accelerometer); audio level and uplink speed are simulated.
class PreflightCheckScreen extends ConsumerStatefulWidget {
  const PreflightCheckScreen({super.key});

  @override
  ConsumerState<PreflightCheckScreen> createState() =>
      _PreflightCheckScreenState();
}

class _PreflightCheckScreenState extends ConsumerState<PreflightCheckScreen> {
  // Captured once, rather than via ref.read() inside dispose(): navigating
  // away now happens after an async gap (goLive() awaits the cloud call
  // before pushReplacementNamed), and by the time dispose() runs in that
  // sequence, the widget's ref can already be disposed — reading fresh
  // from it there throws. Calling a method on an already-obtained notifier
  // instance doesn't have that problem.
  late final PreflightNotifier _preflightNotifier;

  @override
  void initState() {
    super.initState();
    _preflightNotifier = ref.read(preflightProvider.notifier);
    Future.microtask(_preflightNotifier.start);
  }

  @override
  void dispose() {
    _preflightNotifier.stop();
    super.dispose();
  }

  Future<void> _handleStartBroadcast() async {
    final success = await ref.read(broadcastSessionProvider.notifier).goLive();
    if (!success || !mounted) return;
    ref.read(selectedShellTabProvider.notifier).select(ShellTab.live);
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final preflight = ref.watch(preflightProvider);
    final session = ref.watch(broadcastSessionProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Pre-Flight Check')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: AppSpacing.screenPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _CheckRow(
                        label: 'Horizon tilt',
                        value: '${preflight.tiltDegrees.toStringAsFixed(1)}°',
                        ok: preflight.tiltOk,
                      ),
                      const Divider(),
                      Text(
                        'Audio level',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: preflight.audioLevel.clamp(0, 1),
                          minHeight: 10,
                          backgroundColor: AppColors.surfaceMuted,
                        ),
                      ),
                      const Divider(),
                      _CheckRow(
                        label: 'Uplink speed',
                        value:
                            '${preflight.uplinkMbps.toStringAsFixed(1)} Mbps',
                        ok: preflight.uplinkOk,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              if (!preflight.passed)
                const Text(
                  'Broadcast start is blocked until tilt is under 10° and '
                  'uplink is at least 2.0 Mbps.',
                  style: TextStyle(color: AppColors.error),
                ),
              if (session.error != null)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Text(
                    session.error!,
                    style: const TextStyle(color: AppColors.error),
                  ),
                ),
              const SizedBox(height: AppSpacing.md),
              FilledButton(
                onPressed: preflight.passed && !session.isConnecting
                    ? _handleStartBroadcast
                    : null,
                child: session.isConnecting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Start Broadcast'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CheckRow extends StatelessWidget {
  const _CheckRow({required this.label, required this.value, required this.ok});

  final String label;
  final String value;
  final bool ok;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.titleSmall),
        ),
        Text(value),
        const SizedBox(width: 12),
        StatusPill.okFail(label: ok ? 'OK' : 'FAIL', ok: ok),
      ],
    );
  }
}
