import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../auth/application/user_profile_provider.dart';
import '../../dashboard/application/dashboard_providers.dart';
import '../application/business_setup_controller.dart';
import '../domain/business_setup_data.dart';
import 'steps/business_details_step.dart';
import 'steps/business_location_step.dart';
import 'steps/business_review_step.dart';
import 'steps/financial_settings_step.dart';
import 'steps/receipt_settings_step.dart';
import 'widgets/setup_navigation_buttons.dart';
import 'widgets/setup_progress_indicator.dart';

class BusinessSetupScreen extends ConsumerWidget {
  const BusinessSetupScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(businessSetupControllerProvider, (previous, next) {
      if (next.errorMessage != null &&
          next.errorMessage != previous?.errorMessage) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(next.errorMessage!)));
      }
      if (next.finishedBusinessId != null &&
          next.finishedBusinessId != previous?.finishedBusinessId) {
        ref.invalidate(activeBusinessProvider);
        ref.invalidate(currentUserProfileProvider);
        context.go(AppRoutes.home);
      }
    });

    final state = ref.watch(businessSetupControllerProvider);
    final controller = ref.read(businessSetupControllerProvider.notifier);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) {
          return;
        }
        if (state.currentStep != BusinessSetupStep.businessDetails) {
          controller.goToPreviousStep();
          return;
        }
        if (!state.hasUnsavedChanges) {
          context.pop();
          return;
        }
        final shouldLeave = await _confirmLeave(context);
        if (shouldLeave && context.mounted) {
          context.pop();
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(title: const Text('Business Setup')),
        body: SafeArea(
          child: state.isInitializing
              ? const Center(child: CircularProgressIndicator())
              : LayoutBuilder(
                  builder: (context, constraints) {
                    return SingleChildScrollView(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight - AppSpacing.lg,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            SetupProgressIndicator(
                              currentStep: state.currentStepNumber,
                              totalSteps: BusinessSetupStep.values.length,
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            IndexedStack(
                              index: state.currentStep.index,
                              children: <Widget>[
                                BusinessDetailsStep(
                                  data: state.data,
                                  onChanged: controller.setBusinessDetails,
                                ),
                                BusinessLocationStep(
                                  data: state.data,
                                  onChanged: controller.setContactAndLocation,
                                ),
                                FinancialSettingsStep(
                                  data: state.data,
                                  onChanged: controller.setFinancialSettings,
                                ),
                                ReceiptSettingsStep(
                                  settings: state.data.receiptSettings,
                                  onChanged: controller.setReceiptSettings,
                                ),
                                BusinessReviewStep(
                                  data: state.data,
                                  onEdit: controller.jumpToStep,
                                ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.xl),
                            SetupNavigationButtons(
                              showBack:
                                  state.currentStep !=
                                  BusinessSetupStep.businessDetails,
                              isLastStep: state.isLastStep,
                              isLoading: state.isSubmitting,
                              onBack: () => controller.goToPreviousStep(),
                              onNext: () => controller.goToNextStep(),
                              onFinish: controller.submitSetup,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }

  Future<bool> _confirmLeave(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Leave business setup?'),
          content: const Text('Your information has not been saved yet.'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Stay'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Leave'),
            ),
          ],
        );
      },
    );

    return result ?? false;
  }
}
