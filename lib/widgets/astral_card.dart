import 'package:flutter/material.dart';

/// A frosted, rounded content card with a subtle border, matching the astral
/// design language. Used for every dashboard tile.
class AstralCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double? maxWidth;
  final VoidCallback? onTap;

  const AstralCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.maxWidth,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth ?? double.infinity),
      child: Card(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// A titled section header used atop a row of content.
class SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget? trailing;

  const SectionHeader({
    super.key,
    required this.title,
    required this.icon,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 20, color: scheme.primary),
        const SizedBox(width: 10),
        Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const Spacer(),
        if (trailing != null) trailing!,
      ],
    );
  }
}
