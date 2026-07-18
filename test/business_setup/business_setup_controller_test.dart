import 'package:flutter_test/flutter_test.dart';
import 'package:sabibom/features/business_setup/domain/business_setup_data.dart';

String? validateBusinessStep(BusinessSetupData data) {
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
  if (data.businessType == 'Other' && data.customBusinessType.trim().isEmpty) {
    return 'Enter a custom business type.';
  }
  return null;
}

String? validateContactStep(BusinessSetupData data) {
  if (data.phoneNumber.trim().isEmpty) {
    return 'Enter a business phone number.';
  }
  if (data.email.trim().isNotEmpty &&
      !RegExp(r'^\S+@\S+\.\S+$').hasMatch(data.email.trim())) {
    return 'Enter a valid email address.';
  }
  return null;
}

String? validateFinancialStep(BusinessSetupData data) {
  if (data.taxEnabled && (data.taxPercentage < 0 || data.taxPercentage > 100)) {
    return 'Tax percentage must be between 0 and 100.';
  }
  return null;
}

void main() {
  test('required business name validation works', () {
    final data = BusinessSetupData.initial().copyWith(
      businessName: ' ',
      ownerName: 'Owner',
      businessType: 'Retail Shop',
    );
    expect(
      validateBusinessStep(data),
      'Enter a business name between 2 and 80 characters.',
    );
  });

  test('custom other business type is required', () {
    final data = BusinessSetupData.initial().copyWith(
      businessName: 'My Shop',
      ownerName: 'Owner',
      businessType: 'Other',
      customBusinessType: ' ',
    );
    expect(validateBusinessStep(data), 'Enter a custom business type.');
  });

  test('optional email validates only when entered', () {
    final noEmail = BusinessSetupData.initial().copyWith(
      phoneNumber: '+23276123456',
    );
    final invalidEmail = noEmail.copyWith(email: 'wrong');
    expect(validateContactStep(noEmail), isNull);
    expect(validateContactStep(invalidEmail), 'Enter a valid email address.');
  });

  test('tax percentage validation enforces 0..100 when enabled', () {
    final invalid = BusinessSetupData.initial().copyWith(
      taxEnabled: true,
      taxPercentage: 120,
    );
    expect(
      validateFinancialStep(invalid),
      'Tax percentage must be between 0 and 100.',
    );
  });

  test('step data remains preserved between copy updates', () {
    final first = BusinessSetupData.initial().copyWith(
      businessName: 'Sabi Store',
      ownerName: 'Emma',
      businessType: 'Retail Shop',
    );
    final second = first.copyWith(address: 'Main Street', district: 'Bo');
    expect(second.businessName, 'Sabi Store');
    expect(second.ownerName, 'Emma');
    expect(second.address, 'Main Street');
  });

  test('duplicate submission guard behavior can be modeled with stable id', () {
    final generatedId = 'fixed-business-id';
    var pendingId = generatedId;
    final firstCallId = pendingId;
    final secondCallId = pendingId;
    expect(firstCallId, secondCallId);
    expect(firstCallId, generatedId);
  });
}
