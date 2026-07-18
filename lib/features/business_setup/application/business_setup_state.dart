import '../domain/business_setup_data.dart';

class BusinessSetupState {
  const BusinessSetupState({
    required this.currentStep,
    required this.data,
    required this.isInitializing,
    required this.isSubmitting,
    required this.errorMessage,
    required this.pendingBusinessId,
    required this.hasUnsavedChanges,
    required this.finishedBusinessId,
  });

  factory BusinessSetupState.initial() {
    return BusinessSetupState(
      currentStep: BusinessSetupStep.businessDetails,
      data: BusinessSetupData.initial(),
      isInitializing: true,
      isSubmitting: false,
      errorMessage: null,
      pendingBusinessId: null,
      hasUnsavedChanges: false,
      finishedBusinessId: null,
    );
  }

  final BusinessSetupStep currentStep;
  final BusinessSetupData data;
  final bool isInitializing;
  final bool isSubmitting;
  final String? errorMessage;
  final String? pendingBusinessId;
  final bool hasUnsavedChanges;
  final String? finishedBusinessId;

  bool get isLastStep => currentStep == BusinessSetupStep.review;

  int get currentStepNumber => currentStep.index + 1;

  BusinessSetupState copyWith({
    BusinessSetupStep? currentStep,
    BusinessSetupData? data,
    bool? isInitializing,
    bool? isSubmitting,
    String? errorMessage,
    bool clearError = false,
    String? pendingBusinessId,
    bool clearPendingBusinessId = false,
    bool? hasUnsavedChanges,
    String? finishedBusinessId,
    bool clearFinishedBusinessId = false,
  }) {
    return BusinessSetupState(
      currentStep: currentStep ?? this.currentStep,
      data: data ?? this.data,
      isInitializing: isInitializing ?? this.isInitializing,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
      pendingBusinessId: clearPendingBusinessId
          ? null
          : pendingBusinessId ?? this.pendingBusinessId,
      hasUnsavedChanges: hasUnsavedChanges ?? this.hasUnsavedChanges,
      finishedBusinessId: clearFinishedBusinessId
          ? null
          : finishedBusinessId ?? this.finishedBusinessId,
    );
  }
}
