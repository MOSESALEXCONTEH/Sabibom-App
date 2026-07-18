import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/theme/app_spacing.dart';
import '../../auth/application/user_profile_provider.dart';

class BusinessSetupChoiceScreen extends StatefulWidget {
  const BusinessSetupChoiceScreen({super.key});

  @override
  State<BusinessSetupChoiceScreen> createState() => _BusinessSetupChoiceScreenState();
}

class _BusinessSetupChoiceScreenState extends State<BusinessSetupChoiceScreen> {
  var _isSaving = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Spacer(),
              Icon(Icons.storefront_outlined, size: 56, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: AppSpacing.lg),
              Text('Set up your business', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Add your business details now to start tracking sales, stock, customers and expenses. You can also do this later from Settings.',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: AppSpacing.xl),
              FilledButton(
                onPressed: _isSaving ? null : () => _choose('in_progress', AppRoutes.businessSetup),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
                child: const Text('Set Up Now'),
              ),
              const SizedBox(height: AppSpacing.md),
              OutlinedButton(
                onPressed: _isSaving ? null : () => _choose('skipped', AppRoutes.dashboard),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(54)),
                child: const Text('Do It Later'),
              ),
              const Spacer(flex: 2),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _choose(String status, String destination) async {
    setState(() => _isSaving = true);
    try {
      await updateBusinessSetupPreference(status: status, promptSeen: true);
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('Business setup preference sync failed: $error');
        debugPrint('$stackTrace');
      }
    }
    if (mounted) context.go(destination);
  }
}