import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// Shared bottom-tab chrome constants so every tab (Dashboard, Sales,
/// Products, Customers, More, ...) reserves the same clearance above the
/// floating [ModernBottomNavigation] pill instead of guessing a magic number
/// per screen.
abstract final class AppTabChrome {
  /// Bottom inset scrollable content should reserve so the last item isn't
  /// obscured by the floating bottom navigation bar.
  static const bottomInset = 120.0;
}

/// Standardized "no-AppBar tab" page chrome: a title/subtitle header row
/// (with optional trailing action) followed by a flexible body, using
/// consistent [AppSpacing] padding. Used by the primary bottom-nav tabs so
/// title placement, padding and typography stay identical across screens.
///
/// The [body] is responsible for its own scroll/bottom padding; use
/// [AppTabChrome.bottomInset] at the end of any [ListView]/[CustomScrollView]
/// so content isn't hidden behind the floating nav bar.
class AppTabPageScaffold extends StatelessWidget {
  const AppTabPageScaffold({
    required this.title,
    required this.body,
    this.subtitle,
    this.trailing,
    this.floatingActionButton,
    super.key,
  });

  /// Large page title (e.g. "Sales", "Products").
  final String title;

  /// Optional supporting copy shown under the title.
  final String? subtitle;

  /// Optional trailing widget rendered to the right of the header (e.g. a
  /// filter button or summary chip).
  final Widget? trailing;

  /// Main scrollable/flexible content.
  final Widget body;

  final Widget? floatingActionButton;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      floatingActionButton: floatingActionButton,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                0,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          title,
                          style: textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (subtitle != null) ...<Widget>[
                          const SizedBox(height: 4),
                          Text(subtitle!, style: textTheme.bodyMedium),
                        ],
                      ],
                    ),
                  ),
                  ?trailing,
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }
}
