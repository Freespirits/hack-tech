import 'package:flutter/material.dart';

class VitalCard extends StatelessWidget {
  const VitalCard({
    super.key,
    required this.label,
    required this.value,
    required this.unit,
    this.subtitle,
    this.alarm = false,
    this.warn = false,
  });

  final String label;
  final String value;
  final String unit;
  final String? subtitle;
  final bool alarm;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = alarm
        ? scheme.errorContainer
        : warn
            ? scheme.tertiaryContainer
            : scheme.surfaceContainerHighest;
    final fg = alarm
        ? scheme.onErrorContainer
        : warn
            ? scheme.onTertiaryContainer
            : scheme.onSurface;

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: Theme.of(context)
                  .textTheme
                  .labelMedium
                  ?.copyWith(color: fg.withOpacity(0.8))),
          const Spacer(),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.w700,
                  color: fg,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 4),
              Text(
                unit,
                style: TextStyle(
                  color: fg.withOpacity(0.7),
                ),
              ),
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle!,
                style: TextStyle(color: fg.withOpacity(0.7), fontSize: 12)),
          ],
        ],
      ),
    );
  }
}
