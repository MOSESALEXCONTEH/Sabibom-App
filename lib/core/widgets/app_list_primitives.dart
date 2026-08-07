import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Compact section header used above grouped lists (More screen, settings
/// groups, ops hubs). Keeps typography and spacing consistent.
class AppSectionHeader extends StatelessWidget {
  const AppSectionHeader(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: context.mutedTextColor,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

/// Elevated surface wrapping a group of related list rows. Prefer this over
/// stacking bare [Card]s so section chrome stays identical across features.
class AppSectionCard extends StatelessWidget {
  const AppSectionCard({
    required this.children,
    this.padding = EdgeInsets.zero,
    super.key,
  });

  final List<Widget> children;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }
}

/// Shared list-row primitive used by Sales / Products / Customers / Ops lists.
/// Replaces the repeated "Card > ListTile" boilerplate with one consistent
/// look: leading avatar, title, subtitle, optional trailing.
class AppListRow extends StatelessWidget {
  const AppListRow({
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.isThreeLine = false,
    super.key,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool isThreeLine;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: onTap != null,
      label: subtitle == null ? title : '$title, $subtitle',
      container: true,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          onTap: onTap,
          minTileHeight: 56,
          leading: leading,
          isThreeLine: isThreeLine && subtitle != null,
          title: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: subtitle == null
              ? null
              : Text(
                  subtitle!,
                  maxLines: isThreeLine ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
                ),
          trailing: trailing,
        ),
      ),
    );
  }
}

/// Circular brand-tinted avatar used as a list-row leading widget.
class AppListAvatar extends StatelessWidget {
  const AppListAvatar({this.icon, this.label, this.size = 40, super.key})
    : assert(icon != null || label != null);

  final IconData? icon;
  final String? label;
  final double size;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: context.brandTint,
      child: label != null
          ? Text(
              label!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w700,
                fontSize: size * 0.35,
              ),
            )
          : Icon(
              icon,
              color: Theme.of(context).colorScheme.primary,
              size: size * 0.5,
            ),
    );
  }
}
