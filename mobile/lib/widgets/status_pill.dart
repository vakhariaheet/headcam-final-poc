import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The five states design.md §8 defines status language around. Each maps
/// to a fixed icon + color so state is never conveyed by color alone.
enum StatusKind { connected, streaming, standby, offline, live }

class _StatusVisual {
  const _StatusVisual(this.color, this.icon);
  final Color color;
  final IconData icon;
}

const _visuals = {
  StatusKind.connected: _StatusVisual(AppColors.success, Icons.check_circle),
  StatusKind.streaming: _StatusVisual(AppColors.blue500, Icons.podcasts),
  StatusKind.standby: _StatusVisual(AppColors.warning, Icons.pause_circle),
  StatusKind.offline: _StatusVisual(AppColors.error, Icons.error),
  StatusKind.live: _StatusVisual(AppColors.live, Icons.circle),
};

/// A status indicator combining icon + color + label (design.md §8) —
/// status must never rely on color alone.
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.label, required this.kind});

  /// Convenience constructor for the common connected/offline binary.
  const StatusPill.okFail({super.key, required this.label, required bool ok})
    : kind = ok ? StatusKind.connected : StatusKind.offline;

  final String label;
  final StatusKind kind;

  @override
  Widget build(BuildContext context) {
    final visual = _visuals[kind]!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: visual.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: visual.color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(visual.icon, color: visual.color, size: 16),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(color: visual.color, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
