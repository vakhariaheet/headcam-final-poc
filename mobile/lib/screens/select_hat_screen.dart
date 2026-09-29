import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/hat_device.dart';
import '../state/hat_connection_provider.dart';
import '../theme/app_theme.dart';

/// "Choose Existing Hat": lists already-paired hats ([pairedHatIdsProvider])
/// that are currently reachable in a live BLE scan — "active" means
/// showing up in this scan, not just "paired at some point."
class SelectHatScreen extends ConsumerStatefulWidget {
  const SelectHatScreen({super.key});

  @override
  ConsumerState<SelectHatScreen> createState() => _SelectHatScreenState();
}

class _SelectHatScreenState extends ConsumerState<SelectHatScreen> {
  final _found = <HatDevice>[];
  var _scanning = true;

  @override
  void initState() {
    super.initState();
    _scan();
  }

  Future<void> _scan() async {
    final service = ref.read(hatConnectionServiceProvider);
    await for (final device in service.scan()) {
      if (!mounted) return;
      setState(() => _found.add(device));
    }
    if (mounted) setState(() => _scanning = false);
  }

  Future<void> _select(HatDevice device) async {
    await ref.read(hatConnectionProvider.notifier).connect(device);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final pairedIds = ref.watch(pairedHatIdsProvider).valueOrNull ?? const [];
    final activePaired = _found.where((d) => pairedIds.contains(d.id)).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Choose a Hat')),
      body: SafeArea(
        child: Padding(
          padding: AppSpacing.screenPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_scanning)
                const Padding(
                  padding: EdgeInsets.only(bottom: AppSpacing.md),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 12),
                      Text('Looking for your paired hats...'),
                    ],
                  ),
                ),
              Expanded(
                child: activePaired.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _scanning ? 'Searching...' : 'None of your paired hats are nearby right now.',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            if (!_scanning) ...[
                              const SizedBox(height: AppSpacing.md),
                              OutlinedButton(
                                onPressed: () =>
                                    Navigator.of(context)
                                        .pushReplacementNamed('/discovery'),
                                child: const Text('Pair a New Hat'),
                              ),
                            ],
                          ],
                        ),
                      )
                    : ListView.separated(
                        itemCount: activePaired.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: AppSpacing.xs),
                        itemBuilder: (context, index) {
                          final device = activePaired[index];
                          return Card(
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 6,
                              ),
                              leading: Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: AppColors.surfaceMuted,
                                  borderRadius: BorderRadius.circular(
                                    AppRadius.small,
                                  ),
                                ),
                                child: const Icon(
                                  Icons.bluetooth,
                                  color: AppColors.blue500,
                                ),
                              ),
                              title: Text(
                                device.name,
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              subtitle: Text('RSSI ${device.rssi} dBm'),
                              trailing: const Icon(
                                Icons.chevron_right,
                                color: AppColors.textSecondary,
                              ),
                              onTap: () => _select(device),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
