import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/widgets.dart';

import '../data/business_repository.dart';
import '../data/firestore_business_repository.dart';
import 'business_setup_providers.dart';
import '../domain/business_setup_data.dart';
import '../domain/receipt_settings.dart';
import 'business_setup_state.dart';

class BusinessSetupController extends Notifier<BusinessSetupState> {
  @override
  BusinessSetupState build() {
    Future<void>.microtask(_initialize);
    return BusinessSetupState.initial();
  }

  BusinessRepository get _repository => ref.read(businessRepositoryProvider);

  Future<void> _initialize() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      state = state.copyWith(
        isInitializing: false,
        errorMessage: 'Please sign in again to continue business setup.',
      );
      return;
    }

    try {
      final status = await _repository.getUserSetupStatus(user.uid);
      final prefilledData = state.data.copyWith(
        ownerName: status.fullName?.trim().isNotEmpty == true
            ? status.fullName!.trim()
            : (user.displayName ?? ''),
        phoneNumber: status.phoneNumber?.trim().isNotEmpty == true
            ? status.phoneNumber!.trim()
            : (user.phoneNumber ?? ''),
      );

      state = state.copyWith(
        data: _prefillReceiptFromData(prefilledData),
        isInitializing: false,
        hasUnsavedChanges: false,
      );

      if (status.businessSetupCompleted &&
          status.activeBusinessId != null &&
          status.activeBusinessId!.isNotEmpty) {
        state = state.copyWith(
          finishedBusinessId: status.activeBusinessId,
          hasUnsavedChanges: false,
        );
      }
    } on BusinessSetupException catch (error) {
      state = state.copyWith(
        isInitializing: false,
        errorMessage: _friendlyErrorMessage(error.code),
      );
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('Business setup init error: $error');
        debugPrint('$stackTrace');
      }
      state = state.copyWith(
        isInitializing: false,
        errorMessage:
            'Something went wrong while setting up your business. Please try again.',
      );
    }
  }

  void setBusinessDetails({
    String? businessName,
    String? businessType,
    String? customBusinessType,
    String? ownerName,
    String? logoPath,
    bool clearLogoPath = false,
  }) {
    var updated = state.data.copyWith(
      businessName: businessName,
      businessType: businessType,
      customBusinessType: customBusinessType,
      ownerName: ownerName,
      logoPath: logoPath,
      clearLogoPath: clearLogoPath,
    );
    updated = _prefillReceiptFromData(updated);
    state = state.copyWith(
      data: updated,
      hasUnsavedChanges: true,
      clearError: true,
    );
  }

  void setContactAndLocation({
    String? phoneNumber,
    String? email,
    String? address,
    String? district,
    String? customDistrict,
    String? country,
  }) {
    var updated = state.data.copyWith(
      phoneNumber: phoneNumber,
      email: email,
      address: address,
      district: district,
      customDistrict: customDistrict,
      country: country,
    );
    updated = _prefillReceiptFromData(updated);
    state = state.copyWith(
      data: updated,
      hasUnsavedChanges: true,
      clearError: true,
    );
  }

  void setFinancialSettings({
    CurrencyConfig? currency,
    bool? taxEnabled,
    double? taxPercentage,
    String? financialYearStartMonth,
  }) {
    final normalizedTaxEnabled = taxEnabled ?? state.data.taxEnabled;
    final normalizedTax = normalizedTaxEnabled
        ? (taxPercentage ?? state.data.taxPercentage)
        : 0;
    state = state.copyWith(
      data: state.data.copyWith(
        currency: currency,
        taxEnabled: normalizedTaxEnabled,
        taxPercentage: normalizedTax.toDouble(),
        financialYearStartMonth: financialYearStartMonth,
      ),
      hasUnsavedChanges: true,
      clearError: true,
    );
  }

  void setReceiptSettings(ReceiptSettings settings) {
    state = state.copyWith(
      data: state.data.copyWith(receiptSettings: settings),
      hasUnsavedChanges: true,
      clearError: true,
    );
  }

  bool goToNextStep() {
    final validation = validateStep(state.currentStep);
    if (validation != null) {
      state = state.copyWith(errorMessage: validation);
      return false;
    }
    if (state.currentStep == BusinessSetupStep.review) return false;
    state = state.copyWith(
      currentStep: BusinessSetupStep.values[state.currentStep.index + 1],
      clearError: true,
    );
    return true;
  }

  bool goToPreviousStep() {
    if (state.currentStep == BusinessSetupStep.businessDetails) return false;
    state = state.copyWith(
      currentStep: BusinessSetupStep.values[state.currentStep.index - 1],
      clearError: true,
    );
    return true;
  }

  void jumpToStep(BusinessSetupStep step) {
    state = state.copyWith(currentStep: step, clearError: true);
  }

  String? validateStep(BusinessSetupStep step) {
    final data = state.data;
    if (step == BusinessSetupStep.businessDetails) {
      final name = data.businessName.trim();
      if (name.isEmpty || name.length < 2 || name.length > 80) {
        return 'Enter a business name between 2 and 80 characters.';
      }
      if (data.ownerName.trim().isEmpty) {
        return 'Enter the business owner name.';
      }
      if (data.businessType.isEmpty) {
        return 'Select a business type.';
      }
      if (data.businessType == 'Other' &&
          data.customBusinessType.trim().isEmpty) {
        return 'Enter a custom business type.';
      }
    }

    if (step == BusinessSetupStep.contactAndLocation) {
      if (data.phoneNumber.trim().isEmpty) {
        return 'Enter a business phone number.';
      }
      if (!_isValidPhone(data.phoneNumber.trim())) {
        return 'Enter a valid phone number.';
      }
      if (data.address.trim().isEmpty) {
        return 'Enter your business address.';
      }
      if (data.district.isEmpty) {
        return 'Select a district.';
      }
      if (data.district == 'Other' && data.customDistrict.trim().isEmpty) {
        return 'Enter your district or area.';
      }
      if (data.email.trim().isNotEmpty && !_isValidEmail(data.email.trim())) {
        return 'Enter a valid email address.';
      }
    }

    if (step == BusinessSetupStep.financialSettings) {
      if (data.taxEnabled &&
          (data.taxPercentage < 0 ||
              data.taxPercentage > 100 ||
              !data.taxPercentage.isFinite)) {
        return 'Tax percentage must be a valid number between 0 and 100.';
      }
    }

    if (step == BusinessSetupStep.receiptSettings) {
      final receiptName = data.receiptSettings.businessName.trim();
      if (receiptName.isEmpty || receiptName.length < 2) {
        return 'Receipt business name must be at least 2 characters.';
      }
      final receiptPhone = data.receiptSettings.phoneNumber.trim();
      if (receiptPhone.isEmpty) {
        return 'Receipt phone number is required.';
      }
      if (!_isValidPhone(receiptPhone)) {
        return 'Enter a valid receipt phone number.';
      }
    }

    return null;
  }

  Future<void> submitSetup() async {
    if (state.isSubmitting) return;

    FocusManager.instance.primaryFocus?.unfocus();

    final validation =
        validateStep(BusinessSetupStep.review) ??
        validateStep(BusinessSetupStep.businessDetails) ??
        validateStep(BusinessSetupStep.contactAndLocation) ??
        validateStep(BusinessSetupStep.financialSettings) ??
        validateStep(BusinessSetupStep.receiptSettings);

    if (validation != null) {
      state = state.copyWith(errorMessage: validation);
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      state = state.copyWith(
        errorMessage: 'Please sign in again to continue business setup.',
      );
      return;
    }

    final stableBusinessId = state.pendingBusinessId ?? _generateBusinessId();

    state = state.copyWith(
      isSubmitting: true,
      pendingBusinessId: stableBusinessId,
      clearError: true,
    );

    try {
      final sanitizedData = _sanitizeData(state.data);
      if (kDebugMode) {
        // Excludes sensitive or large fields for cleaner logging.
        final loggableMap = sanitizedData.toLoggableMap();
        debugPrint('Submitting sanitized business setup data: $loggableMap');
      }

      final result = await _repository.createBusinessSetup(
        uid: user.uid,
        businessId: stableBusinessId,
        data: sanitizedData,
      );
      state = state.copyWith(
        isSubmitting: false,
        finishedBusinessId: result.businessId,
        hasUnsavedChanges: false,
      );
    } on BusinessSetupException catch (error, stackTrace) {
      _log(
        operation: error.operation ?? 'submit',
        error: error,
        stackTrace: stackTrace,
        businessId: stableBusinessId,
      );
      state = state.copyWith(
        isSubmitting: false,
        errorMessage: _friendlyErrorMessage(error.code),
      );
    } catch (error, stackTrace) {
      _log(
        operation: 'submit',
        error: error,
        stackTrace: stackTrace,
        businessId: stableBusinessId,
      );
      state = state.copyWith(
        isSubmitting: false,
        errorMessage:
            'Something went wrong while setting up your business. Please try again.',
      );
    }
  }

  void _log({
    required String operation,
    required Object error,
    required StackTrace stackTrace,
    String? businessId,
  }) {
    if (!kDebugMode) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    debugPrint('Business setup controller error ($operation): $error');
    if (error is FirebaseException) {
      debugPrint(
        'Firestore error: code=${error.code}, message=${error.message}, '
        'uid=$uid, businessId=$businessId',
      );
    }
    debugPrintStack(stackTrace: stackTrace);
  }

  String _friendlyErrorMessage(String code) {
    switch (code) {
      case 'network-request-failed':
      case 'unavailable':
      case 'deadline-exceeded':
        return 'Check your internet connection and try again.';
      case 'unauthenticated':
        return 'Your session has expired. Please sign in again.';
      case 'permission-denied':
        return 'We could not save your business profile. Please check your account and try again.';
      case 'already-exists':
        return 'Your business profile has already been created.';
      case 'invalid-argument':
        return 'Some business information is invalid. Review the form and try again.';
      default:
        return 'Something went wrong while setting up your business. Please try again.';
    }
  }

  BusinessSetupData _sanitizeData(BusinessSetupData data) {
    return data.copyWith(
      businessName: data.businessName.trim(),
      customBusinessType: data.customBusinessType.trim(),
      ownerName: data.ownerName.trim(),
      phoneNumber: data.phoneNumber.trim(),
      email: data.email.trim(),
      address: data.address.trim(),
      customDistrict: data.customDistrict.trim(),
      taxPercentage: (data.taxEnabled && data.taxPercentage.isFinite)
          ? data.taxPercentage
          : 0,
      receiptSettings: data.receiptSettings.copyWith(
        businessName: data.receiptSettings.businessName.trim(),
        phoneNumber: data.receiptSettings.phoneNumber.trim(),
        address: data.receiptSettings.address.trim(),
        footerMessage: data.receiptSettings.footerMessage.trim(),
      ),
    );
  }

  BusinessSetupData _prefillReceiptFromData(BusinessSetupData data) {
    return data.copyWith(
      receiptSettings: data.receiptSettings.copyWith(
        businessName: data.receiptSettings.businessName.trim().isNotEmpty
            ? data.receiptSettings.businessName
            : data.businessName,
        phoneNumber: data.receiptSettings.phoneNumber.trim().isNotEmpty
            ? data.receiptSettings.phoneNumber
            : data.phoneNumber,
        address: data.receiptSettings.address.trim().isNotEmpty
            ? data.receiptSettings.address
            : data.address,
      ),
    );
  }

  bool _isValidEmail(String value) {
    return RegExp(r'^\S+@\S+\.\S+$').hasMatch(value);
  }

  bool _isValidPhone(String value) {
    return RegExp(r'^[+]?\d{7,15}$').hasMatch(value.replaceAll(' ', ''));
  }

  String _generateBusinessId() {
    return FirebaseFirestore.instance.collection('businesses').doc().id;
  }
}

final businessSetupControllerProvider =
    NotifierProvider<BusinessSetupController, BusinessSetupState>(
      BusinessSetupController.new,
    );
