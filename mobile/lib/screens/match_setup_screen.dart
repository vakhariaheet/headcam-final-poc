import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/broadcast_channels_provider.dart';
import '../state/match_provider.dart';
import '../state/shell_navigation_provider.dart';
import '../theme/app_theme.dart';

/// Screen 4 (spec §5.1, §6.2): first step of Start Broadcast, reached only
/// once a hat is connected (see home_screen.dart). URL parsing here is
/// real — [parseCricHeroesUrl] implements the spec's exact regex — team
/// names are local placeholders since CricHeroes has no API to resolve
/// them. Which channels to broadcast to isn't chosen here — that's a
/// one-time, user-level setting (see broadcast_channels_provider.dart) —
/// this screen just shows what's already connected and gates Continue on
/// there being at least one.
class MatchSetupScreen extends ConsumerWidget {
  const MatchSetupScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final channels = ref.watch(broadcastChannelsProvider);
    final match = ref.watch(matchSetupProvider);
    final notifier = ref.read(matchSetupProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Match Setup')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: AppSpacing.screenPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Paste the CricHeroes match link shared by the scorer.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                key: const Key('matchUrlField'),
                onChanged: notifier.updateInput,
                decoration: InputDecoration(
                  labelText: 'CricHeroes match URL',
                  errorText: match.error,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              if (match.matchInfo != null)
                Card(
                  key: const Key('matchBadge'),
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: AppColors.surfaceMuted,
                            borderRadius: BorderRadius.circular(
                              AppRadius.control,
                            ),
                          ),
                          child: const Icon(
                            Icons.sports_cricket,
                            color: AppColors.blue500,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${match.matchInfo!.teamAName} vs ${match.matchInfo!.teamBName}',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              Text(
                                'Match ID: ${match.matchInfo!.matchId}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Text(
                      'Paste a link to see the match preview here.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'BROADCASTING TO',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: AppSpacing.sm),
              if (channels.hasAnyChannel)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Text(
                      [
                        if (channels.googleConnected) 'YouTube',
                        if (channels.metaConnected) 'Facebook',
                      ].join(', '),
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ),
                )
              else
                Card(
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(14),
                    leading: const Icon(Icons.link_off, color: AppColors.error),
                    title: const Text('No channel connected'),
                    subtitle: const Text(
                      'Connect one in Settings to continue.',
                    ),
                    trailing: const Icon(
                      Icons.chevron_right,
                      color: AppColors.textSecondary,
                    ),
                    onTap: () {
                      ref
                          .read(selectedShellTabProvider.notifier)
                          .select(ShellTab.settings);
                      Navigator.of(context).popUntil((route) => route.isFirst);
                    },
                  ),
                ),
              const SizedBox(height: AppSpacing.xl),
              FilledButton(
                onPressed: match.canContinue && channels.hasAnyChannel
                    ? () => Navigator.of(context).pushNamed('/preflight')
                    : null,
                child: const Text('Continue'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
