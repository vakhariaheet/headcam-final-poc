import 'package:flutter/material.dart';

/// A single value+label column, e.g. "82% / Battery" — used by the §12
/// Device Card and the §13 Live console's battery/temperature/signal grid.
class MetricColumn extends StatelessWidget {
  const MetricColumn({super.key, required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 2),
        Text(
          label,
          style: Theme.of(context).textTheme.labelLarge
              ?.copyWith(letterSpacing: 0),
        ),
      ],
    );
  }
}
