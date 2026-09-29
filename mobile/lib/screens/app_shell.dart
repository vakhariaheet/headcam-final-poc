import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/broadcast_session_provider.dart';
import '../state/shell_navigation_provider.dart';
import '../theme/app_theme.dart';
import 'devices_screen.dart';
import 'home_screen.dart';
import 'live_broadcast_screen.dart';
import 'recordings_screen.dart';
import 'settings_screen.dart';

/// The persistent Home · Live · Devices · Recordings · Settings shell
/// (design.md §10) a signed-in umpire lands on. Pairing a hat and starting
/// a broadcast are separate short flows pushed on top of this shell (see
/// home_screen.dart), which redirect back into a specific tab via
/// [selectedShellTabProvider] rather than a standalone `/live` route.
class AppShell extends ConsumerWidget {
  const AppShell({super.key});

  static const _destinations = [
    NavigationDestination(
      icon: Icon(Icons.home_outlined),
      selectedIcon: Icon(Icons.home),
      label: 'Home',
    ),
    NavigationDestination(
      icon: Icon(Icons.podcasts_outlined),
      selectedIcon: Icon(Icons.podcasts),
      label: 'Live',
    ),
    NavigationDestination(
      icon: Icon(Icons.bluetooth),
      selectedIcon: Icon(Icons.bluetooth_connected),
      label: 'Devices',
    ),
    NavigationDestination(
      icon: Icon(Icons.video_library_outlined),
      selectedIcon: Icon(Icons.video_library),
      label: 'Recordings',
    ),
    NavigationDestination(
      icon: Icon(Icons.settings_outlined),
      selectedIcon: Icon(Icons.settings),
      label: 'Settings',
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(selectedShellTabProvider);

    return Scaffold(
      body: IndexedStack(
        index: index,
        children: const [
          HomeScreen(),
          _LiveTab(),
          DevicesScreen(),
          RecordingsScreen(),
          SettingsScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) =>
            ref.read(selectedShellTabProvider.notifier).select(i),
        destinations: _destinations,
      ),
    );
  }
}

/// Live becomes visually prominent while a broadcast is active (§10): this
/// embeds the real [LiveBroadcastView] under the dark broadcast theme when
/// a session is live, otherwise shows an idle placeholder. The view now
/// carries its own "LIVE" + timer header (§13), so no separate AppBar.
class _LiveTab extends ConsumerWidget {
  const _LiveTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isLive = ref.watch(broadcastSessionProvider).isLive;

    if (!isLive) {
      return Scaffold(
        appBar: AppBar(title: const Text('Live')),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: AppSpacing.screenPadding,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.podcasts_outlined,
                    size: 40,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'Not currently broadcasting',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Start a broadcast from Home to see it here.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Theme(
      data: buildLiveTheme(),
      child: const Scaffold(body: SafeArea(child: LiveBroadcastView())),
    );
  }
}
