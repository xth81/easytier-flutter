import 'package:flutter/material.dart';

/// A status pill used to show a short labeled state (e.g. "已连接", "未连接").
class StatusPill extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;
  final bool filled;

  const StatusPill({
    super.key,
    required this.label,
    required this.color,
    this.icon = Icons.circle,
    this.filled = true,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = filled ? color.withValues(alpha: 0.16) : scheme.surfaceContainerLow;
    final fg = filled ? color : scheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
