import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../dashboard/application/dashboard_providers.dart';
import '../domain/setup_checklist.dart';

final setupChecklistServiceProvider = Provider<SetupChecklistService>((ref) {
  return SetupChecklistService();
});

final setupChecklistProvider =
    FutureProvider<SetupChecklistProgress>((ref) async {
  final active = ref.watch(activeBusinessProvider).asData?.value;
  final businessId =
      active is ActiveBusinessData ? active.business.businessId : '';
  return ref.watch(setupChecklistServiceProvider).load(businessId);
});
