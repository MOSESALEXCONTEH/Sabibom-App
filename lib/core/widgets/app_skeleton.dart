import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Shared shimmer wrapper so every skeleton in the app animates identically.
/// Prefer [AppListSkeleton] / [AppCardSkeleton] over a bare
/// [CircularProgressIndicator] for list/section loading states - skeletons
/// communicate expected layout and feel faster than a spinner.
class AppShimmer extends StatelessWidget {
  const AppShimmer({required this.child, this.semanticLabel, super.key});

  final Widget child;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final placeholder = MediaQuery.disableAnimationsOf(context)
        ? child
        : RepaintBoundary(
            child: Shimmer.fromColors(
              baseColor: context.borderColor,
              highlightColor: context.isDarkTheme
                  ? const Color(0xFF3A4356)
                  : const Color(0xFFF3F4F6),
              period: const Duration(milliseconds: 1300),
              child: child,
            ),
          );
    final label = semanticLabel;
    if (label == null) return placeholder;
    return Semantics(
      container: true,
      liveRegion: true,
      label: label,
      child: ExcludeSemantics(child: placeholder),
    );
  }
}

/// A single rounded skeleton block. Building block for bespoke skeleton
/// layouts (e.g. dashboard summary card, metric grid).
class AppSkeletonBlock extends StatelessWidget {
  const AppSkeletonBlock({
    this.width,
    this.height = 16,
    this.borderRadius,
    super.key,
  });

  final double? width;
  final double height;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.borderColor,
        borderRadius: borderRadius ?? BorderRadius.circular(AppRadii.chip),
      ),
      child: SizedBox(width: width, height: height),
    );
  }
}

/// Skeleton placeholder for a vertical list of rows (sales history, product
/// list, customer list, etc.) - mirrors the eventual "avatar + two lines +
/// trailing" row shape so the loading state doesn't jump around once real
/// content arrives.
class AppListSkeleton extends StatelessWidget {
  const AppListSkeleton({
    this.itemCount = 6,
    this.itemHeight = 72,
    this.padding = EdgeInsets.zero,
    super.key,
  });

  final int itemCount;
  final double itemHeight;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return AppShimmer(
      semanticLabel: 'Loading list',
      child: ListView.separated(
        padding: padding,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: itemCount,
        separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
        itemBuilder: (context, index) => SizedBox(
          height: itemHeight,
          child: Row(
            children: <Widget>[
              const AppSkeletonBlock(
                width: 44,
                height: 44,
                borderRadius: BorderRadius.all(Radius.circular(22)),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    const AppSkeletonBlock(width: double.infinity, height: 14),
                    const SizedBox(height: 8),
                    AppSkeletonBlock(
                      width: MediaQuery.sizeOf(context).width * 0.35,
                      height: 12,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              const AppSkeletonBlock(width: 48, height: 14),
            ],
          ),
        ),
      ),
    );
  }
}

/// Skeleton placeholder for a single card/section (dashboard summary card,
/// metric grid, section content) rendered as a rounded block of the given
/// height.
class AppCardSkeleton extends StatelessWidget {
  const AppCardSkeleton({this.height = 120, super.key});

  final double height;

  @override
  Widget build(BuildContext context) {
    return AppShimmer(
      semanticLabel: 'Loading content',
      child: AppSkeletonBlock(
        width: double.infinity,
        height: height,
        borderRadius: BorderRadius.circular(AppRadii.card),
      ),
    );
  }
}
