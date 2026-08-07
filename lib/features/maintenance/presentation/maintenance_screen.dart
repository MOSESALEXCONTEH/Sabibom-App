import 'package:flutter/material.dart';

import '../../../core/theme/app_spacing.dart';
import '../domain/runtime_configuration.dart';

class MaintenanceScreen extends StatelessWidget {
  const MaintenanceScreen({
    required this.configuration,
    required this.onRetry,
    super.key,
  });

  final RuntimeMaintenanceConfiguration configuration;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.build_circle_outlined,
                    size: 72,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    'SabiBom is under maintenance',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    configuration.message,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  if (configuration.endsAt != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      'Expected availability: ${MaterialLocalizations.of(context).formatFullDate(configuration.endsAt!)}',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  const SizedBox(height: AppSpacing.xl),
                  FilledButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Check again'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
