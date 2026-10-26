import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/hat_connection_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/device_card.dart';
import '../widgets/firmware_update_card.dart';

/// Devices tab: the current UmpireHat's connection/health, with a way to
/// (re)pair. This app only ever manages one connected hat at a time today
/// — no multi-device broadcast backend exists — but [pairedHatIdsProvider]
/// does remember every hat this account has paired with before.
class DevicesScreen extends ConsumerWidget {
  const DevicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connection = ref.watch(hatConnectionProvider);
    final isConnected =
        connection.status == HatConnectionStatus.connected ||
        connection.status == HatConnectionStatus.provisioning ||
        connection.status == HatConnectionStatus.provisioned;

    return Scaffold(
      appBar: AppBar(title: const Text('Devices')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: AppSpacing.screenPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DeviceCard(
                onStartBroadcast: () =>
                    Navigator.of(context).pushNamed('/match-setup'),
                onPairNewHat: () =>
                    Navigator.of(context).pushNamed('/discovery'),
                onChooseExistingHat: () =>
                    Navigator.of(context).pushNamed('/select-hat'),
              ),
              if (isConnected) ...[
                const SizedBox(height: AppSpacing.md),
                const FirmwareUpdateCard(),
                const SizedBox(height: AppSpacing.md),
                OutlinedButton(
                  onPressed: () =>
                      Navigator.of(context).pushNamed('/discovery'),
                  child: const Text('Pair a different hat'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
