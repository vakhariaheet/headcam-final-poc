import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The fourth button tier design.md §7 calls out alongside Primary/
/// Secondary/Ghost — for actions like Emergency Kill Switch, Remove
/// Device, Delete Recording. Flutter's theme has no built-in slot for
/// this, so it's a small explicit wrapper rather than a one-off style
/// repeated at each call site.
class DestructiveButton extends StatelessWidget {
  const DestructiveButton({
    super.key,
    required this.onPressed,
    required this.label,
    this.icon,
  });

  final VoidCallback? onPressed;
  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final style = FilledButton.styleFrom(
      backgroundColor: AppColors.error.withValues(alpha: 0.12),
      foregroundColor: AppColors.error,
      minimumSize: const Size.fromHeight(54),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
    );

    if (icon == null) {
      return FilledButton(
        style: style,
        onPressed: onPressed,
        child: Text(label),
      );
    }
    return FilledButton.tonalIcon(
      style: style,
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(label),
    );
  }
}
