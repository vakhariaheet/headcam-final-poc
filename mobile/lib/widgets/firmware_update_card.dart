import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/firmware_update_provider.dart';
import '../state/hat_connection_provider.dart';
import '../theme/app_theme.dart';
import 'hat_connection_messages.dart';

/// The connected hat's firmware version, with checking for and installing
/// updates. The hat downloads the image over its own Wi-Fi.
class FirmwareUpdateCard extends ConsumerWidget {
  const FirmwareUpdateCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(hatConnectionProvider.select((s) => s.info));
    final update = ref.watch(firmwareUpdateProvider);
    final notifier = ref.read(firmwareUpdateProvider.notifier);
    final textTheme = Theme.of(context).textTheme;
    final version = update.release?.version;

    final (String status, Widget? action) = switch (update.phase) {
      FirmwareUpdatePhase.idle => (
        'Check whether a newer version is available.',
        OutlinedButton(
          onPressed: notifier.check,
          child: const Text('Check for updates'),
        ),
      ),
      FirmwareUpdatePhase.checking => ('Checking for updates…', null),
      FirmwareUpdatePhase.upToDate => (
        'Your UmpireHat is up to date.',
        OutlinedButton(
          onPressed: notifier.check,
          child: const Text('Check again'),
        ),
      ),
      FirmwareUpdatePhase.available => (
        'Version $version is available. Keep the hat powered and on Wi-Fi; '
            'it restarts when the update is installed.',
        FilledButton(
          onPressed: notifier.install,
          child: Text('Update to $version'),
        ),
      ),
      FirmwareUpdatePhase.installing => (
        'Installing $version… ${update.percent}%',
        null,
      ),
      FirmwareUpdatePhase.rebooting => (
        'Update installed. Your UmpireHat is restarting with $version; '
            'reconnect in about 30 seconds.',
        null,
      ),
      FirmwareUpdatePhase.failed => (
        hatUpdateFailureMessage(update.failure ?? ''),
        OutlinedButton(
          onPressed: notifier.check,
          child: const Text('Try again'),
        ),
      ),
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text('Firmware', style: textTheme.titleMedium)),
                Text(
                  info?.firmwareVersion ?? '—',
                  key: const Key('firmwareVersion'),
                  style: textTheme.bodyMedium,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(status, style: textTheme.bodyMedium),
            if (update.phase == FirmwareUpdatePhase.installing) ...[
              const SizedBox(height: AppSpacing.sm),
              LinearProgressIndicator(value: update.percent / 100),
            ],
            if (update.phase == FirmwareUpdatePhase.checking) ...[
              const SizedBox(height: AppSpacing.sm),
              const LinearProgressIndicator(),
            ],
            if (action != null) ...[
              const SizedBox(height: AppSpacing.md),
              action,
            ],
          ],
        ),
      ),
    );
  }
}
