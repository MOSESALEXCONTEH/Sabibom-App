import '../domain/business_setup_data.dart';

class UserSetupStatus {
  const UserSetupStatus({
    required this.businessSetupCompleted,
    required this.activeBusinessId,
    this.fullName,
    this.phoneNumber,
  });

  final bool businessSetupCompleted;
  final String? activeBusinessId;
  final String? fullName;
  final String? phoneNumber;
}

class BusinessSetupResult {
  const BusinessSetupResult({
    required this.businessId,
    required this.wasExisting,
  });

  final String businessId;
  final bool wasExisting;
}

abstract class BusinessRepository {
  Future<UserSetupStatus> getUserSetupStatus(String uid);

  Future<BusinessSetupResult> createBusinessSetup({
    required String uid,
    required String businessId,
    required BusinessSetupData data,
  });
}
