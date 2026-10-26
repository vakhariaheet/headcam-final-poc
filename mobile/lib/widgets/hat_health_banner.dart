import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/hat_connection_provider.dart';
import '../theme/app_theme.dart';
import 'hat_connection_messages.dart';

/// Explains camera trouble on the connected hat: a live restart, a hat that
/// has given up and needs a power cycle, or a recent recovery. Renders
/// nothing while the camera is healthy.
class HatHealthBanner extends ConsumerWidget {
  const HatHealthBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fault = ref.watch(hatCameraFaultProvider).valueOrNull;
    final info = ref.watch(hatConnectionProvider.select((s) => s.info));
    final message = hatCameraMessage(fault: fault, info: info);
    if (message == null) return const SizedBox.shrink();
    final severe = hatCameraNeedsPowerCycle(fault: fault, info: info);
    final color = severe ? AppColors.error : AppColors.warning;

    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        key: const Key('hatHealthBanner'),
        margin: const EdgeInsets.only(bottom: AppSpacing.md),
        padding: const EdgeInsets.all(AppSpacing.space3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          border: Border.all(color: color),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              severe ? Icons.error_outline : Icons.warning_amber_rounded,
              color: color,
            ),
            const SizedBox(width: AppSpacing.space3),
            Expanded(
              child: Text(
                message,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
