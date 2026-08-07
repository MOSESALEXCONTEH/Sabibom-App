import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class BranchQueryErrorView {
  const BranchQueryErrorView({
    required this.message,
    required this.referenceId,
  });

  final String message;
  final String referenceId;
}

BranchQueryErrorView branchQueryErrorView(
  Object error, {
  required String queryName,
  required String businessId,
  required String? branchId,
  required int limit,
}) {
  final referenceId =
      '${queryName.substring(0, 1).toUpperCase()}${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';
  final firebaseError = error is FirebaseException ? error : null;
  final code = firebaseError?.code ?? 'unknown';
  final safeMessage = firebaseError?.message?.replaceAll(RegExp(r'\s+'), ' ');
  final selectedBranch = branchId?.trim();
  final nonMain =
      selectedBranch != null &&
      selectedBranch.isNotEmpty &&
      selectedBranch != 'main';

  debugPrint(
    '[branch-query] requestId=$referenceId query=$queryName '
    'branchId=${selectedBranch ?? 'all'} '
    'collection=businesses/$businessId/$queryName '
    'filters=${nonMain ? 'branchId==$selectedBranch' : 'legacy-main-or-all'} '
    'order=createdAt:desc limit=$limit code=$code '
    'message=${safeMessage ?? 'unavailable'}',
  );

  final message = switch (code) {
    'failed-precondition'
        when safeMessage?.toLowerCase().contains('index') == true =>
      'This branch view is still being prepared. Please try again shortly.',
    'permission-denied' => 'You do not have permission to view this branch.',
    'unavailable' =>
      'Could not connect. Check your internet connection and try again.',
    _ => 'Could not load records. Reference: $referenceId',
  };
  return BranchQueryErrorView(message: message, referenceId: referenceId);
}
