import 'package:flutter/material.dart';

/// A frosted, rounded content card with a subtle border, matching the astral
/// design language. Used for every dashboard tile.
///
/// With [onTap] it also provides standard Material ripple feedback.
class AstralCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  const AstralCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}
