import 'package:flutter/material.dart';

import 'astral_card.dart';
import 'section_header.dart';

/// An [AstralCard] with a standard titled header, used by every screen to
/// keep section layout consistent.
///
/// The card grows to the full content width (phones) — the old 560px
/// fixed-width column was removed because it wasted horizontal space on
/// large screens and caused awkward centering.
class SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  const SectionCard({
    super.key,
    required this.title,
    required this.icon,
    required this.child,
    this.trailing,
    this.padding = const EdgeInsets.all(20),
  });

  @override
  Widget build(BuildContext context) {
    return AstralCard(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(title: title, icon: icon, trailing: trailing),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}
