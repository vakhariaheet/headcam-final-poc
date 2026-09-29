import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/broadcast_channels_provider.dart';
import '../state/shell_navigation_provider.dart';
import '../state/user_auth_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/brand_header.dart';
import '../widgets/device_card.dart';

String _greeting() {
  final hour = DateTime.now().hour;
  if (hour < 12) return 'Good morning';
  if (hour < 17) return 'Good afternoon';
  return 'Good evening';
}

/// Home (design.md §11): "Is my UmpireHat ready? What's its health? Can I
/// start broadcasting? What did I record recently?" — the app's landing
/// screen after sign-in. Pairing a hat and starting a broadcast are two
/// separate, short flows reached from here (see [DeviceCard]), not one
/// long combined wizard.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(userAuthProvider).currentUser;
    final channels = ref.watch(broadcastChannelsProvider);

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: AppSpacing.screenPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const BrandHeader(compact: true),
              const SizedBox(height: AppSpacing.md),
              Text(
                user != null
                    ? '${_greeting()}, ${user.displayName}'
                    : _greeting(),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: AppSpacing.lg),
              DeviceCard(
                onStartBroadcast: () =>
                    Navigator.of(context).pushNamed('/match-setup'),
                onPairNewHat: () =>
                    Navigator.of(context).pushNamed('/discovery'),
                onChooseExistingHat: () =>
                    Navigator.of(context).pushNamed('/select-hat'),
              ),
              if (!channels.hasAnyChannel) ...[
                const SizedBox(height: AppSpacing.md),
                Card(
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(14),
                    leading: const Icon(Icons.link, color: AppColors.blue500),
                    title: const Text('Connect a broadcast channel'),
                    subtitle: const Text(
                      'YouTube or Facebook, connected once.',
                    ),
                    trailing: const Icon(
                      Icons.chevron_right,
                      color: AppColors.textSecondary,
                    ),
                    onTap: () => ref
                        .read(selectedShellTabProvider.notifier)
                        .select(ShellTab.settings),
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              Text(
                'Recent Recordings',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.sm),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Text(
                    'No recordings yet.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
