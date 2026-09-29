import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/broadcast_channels_provider.dart';
import '../state/user_auth_provider.dart';
import '../theme/app_theme.dart';

/// Settings tab: account info, sign out, and the one-time "Connected
/// Channels" section (moved here from the now-deleted
/// broadcast_channels_screen.dart — see broadcast_channels_provider.dart's
/// doc comment for why that connection is user-level, not per-broadcast).
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(userAuthProvider).currentUser;
    final channels = ref.watch(broadcastChannelsProvider);
    final channelsNotifier = ref.read(broadcastChannelsProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: ListView(
          padding: AppSpacing.screenPadding,
          children: [
            if (user != null)
              Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.all(14),
                  leading: const Icon(
                    Icons.person_outline,
                    color: AppColors.textSecondary,
                  ),
                  title: Text(user.displayName),
                  subtitle: Text(user.email),
                ),
              ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'CONNECTED CHANNELS',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Connect once — the umpire won\'t need to sign in again before '
              'each broadcast.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            _ChannelCard(
              icon: Icons.smart_display_outlined,
              label: 'YouTube Live',
              subtitle: 'Google account · YouTube Data API v3',
              connected: channels.googleConnected,
              onPressed: channelsNotifier.signInWithGoogle,
            ),
            const SizedBox(height: AppSpacing.sm),
            _ChannelCard(
              icon: Icons.facebook_outlined,
              label: 'Facebook Live',
              subtitle: 'Meta account · Facebook Pages API',
              connected: channels.metaConnected,
              onPressed: channelsNotifier.signInWithMeta,
            ),
            const SizedBox(height: AppSpacing.lg),
            Card(
              child: ListTile(
                contentPadding: const EdgeInsets.all(14),
                leading: const Icon(Icons.logout, color: AppColors.error),
                title: const Text('Sign out'),
                onTap: () async {
                  await ref.read(userAuthProvider.notifier).logOut();
                  if (context.mounted) {
                    Navigator.of(context)
                        .pushNamedAndRemoveUntil('/login', (_) => false);
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChannelCard extends StatelessWidget {
  const _ChannelCard({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.connected,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final bool connected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.card),
        onTap: connected ? null : onPressed,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.surfaceMuted,
                  borderRadius: BorderRadius.circular(AppRadius.control),
                ),
                child: Icon(icon, color: AppColors.blue500),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: Theme.of(context).textTheme.titleMedium),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (connected)
                const Icon(Icons.check_circle, color: AppColors.blue500)
              else
                const Icon(Icons.chevron_right, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}
