import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../notifications/data/notifications_repository.dart';
import '../../team/application/team_providers.dart';
import '../../team/data/team_repository.dart';
import '../../team/domain/app_permission.dart';
import '../../team/domain/approval_models.dart';
import '../../team/domain/business_membership.dart';
import '../../team/domain/staff_activity.dart';
import '../../team/domain/team_exception.dart';
import '../data/firestore_sales_repository.dart';
import '../data/sales_repository.dart';
import 'sales_providers.dart';

enum SaleVoidOutcome { voided, approvalRequested }

class SaleVoidService {
  SaleVoidService({
    required this.salesRepository,
    required this.teamRepository,
    required this.notificationsRepository,
  });

  final SalesRepository salesRepository;
  final TeamRepository teamRepository;
  final NotificationsRepository notificationsRepository;

  Future<SaleVoidOutcome> voidOrRequestApproval({
    required String businessId,
    required String branchId,
    required String saleId,
    required String receiptNumber,
    required String reason,
    required BusinessMembership? membership,
    required ApprovalPolicies policies,
    required int totalMinor,
    String? currencySymbol,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw const SaleException('unauthenticated');

    final canVoid =
        membership?.hasPermission(AppPermission.voidSale) == true ||
        membership?.isOwner == true;
    if (!canVoid) throw TeamException.permissionDenied;

    final canApproveDirectly =
        membership?.isOwner == true ||
        membership?.hasPermission(AppPermission.approveSensitiveActions) ==
            true;
    final needsApproval =
        policies.requireSaleVoidApproval && !canApproveDirectly;

    final actorName =
        membership?.effectiveDisplayName ??
        user.displayName ??
        user.email ??
        'Staff';

    if (needsApproval) {
      final approvalId = await teamRepository.createApprovalRequest(
        ApprovalRequest(
          id: '',
          businessId: businessId,
          type: ApprovalRequestType.voidSale,
          status: ApprovalStatus.pending,
          requestedBy: user.uid,
          requestedByName: actorName,
          requestedByRole: membership?.roleName,
          entityType: 'sale',
          entityId: saleId,
          entitySnapshot: {
            'branchId': branchId,
            'receiptNumber': receiptNumber,
            'totalMinor': totalMinor,
            'currencySymbol': currencySymbol,
            'reason': reason.trim(),
          },
          reason: reason.trim(),
          requestedAt: DateTime.now(),
          expiresAt: DateTime.now().add(const Duration(days: 3)),
        ),
      );

      await teamRepository.logActivity(
        StaffActivity(
          id: '',
          businessId: businessId,
          userId: user.uid,
          userName: actorName,
          userRole: membership?.roleName ?? '',
          actionType: StaffActionType.approvalRequested,
          entityType: 'sale',
          entityId: saleId,
          entityLabel: receiptNumber,
          description: 'Requested approval to void sale $receiptNumber',
        ),
      );

      // Notify owners/managers who can approve.
      final members = await teamRepository
          .watchMembers(businessId)
          .first
          .timeout(const Duration(seconds: 8), onTimeout: () => const []);
      for (final m in members) {
        if (!m.status.canAccessBusiness) continue;
        if (m.uid == user.uid) continue;
        if (!m.hasPermission(AppPermission.approveSensitiveActions) &&
            !m.isOwner) {
          continue;
        }
        await notificationsRepository.createNotification(
          userId: m.uid,
          type: AppNotificationType.approvalRequested,
          title: 'Approval needed',
          body: '$actorName asked to void sale $receiptNumber',
          businessId: businessId,
          branchId: branchId,
          entityType: 'approval',
          entityId: approvalId,
        );
      }

      return SaleVoidOutcome.approvalRequested;
    }

    await salesRepository.voidSale(
      businessId,
      saleId,
      branchId: branchId,
      reason: reason,
      voidedByUid: user.uid,
      voidedByName: actorName,
    );

    await teamRepository.logActivity(
      StaffActivity(
        id: '',
        businessId: businessId,
        userId: user.uid,
        userName: actorName,
        userRole: membership?.roleName ?? '',
        actionType: StaffActionType.saleVoided,
        entityType: 'sale',
        entityId: saleId,
        entityLabel: receiptNumber,
        description: 'Voided sale $receiptNumber',
        metadata: {'reason': reason.trim()},
      ),
    );

    return SaleVoidOutcome.voided;
  }

  /// Executes the underlying sale void after an approval is granted.
  Future<void> executeApprovedVoid({
    required ApprovalRequest approval,
    required String approvedByUid,
    required String approvedByName,
  }) async {
    if (approval.type != ApprovalRequestType.voidSale) {
      throw const TeamException('Unsupported approval type.');
    }
    final reason =
        (approval.reason?.trim().isNotEmpty == true
            ? approval.reason!.trim()
            : approval.entitySnapshot['reason'] as String?) ??
        'Approved void';
    final branchId = approval.entitySnapshot['branchId'] as String?;
    if (branchId == null || branchId.trim().isEmpty) {
      throw const SaleException(
        'failed-precondition',
        message: 'The approval is missing its sale branch.',
      );
    }

    await salesRepository.voidSale(
      approval.businessId,
      approval.entityId,
      branchId: branchId,
      reason: reason,
      voidedByUid: approvedByUid,
      voidedByName: approvedByName,
    );

    await teamRepository.logActivity(
      StaffActivity(
        id: '',
        businessId: approval.businessId,
        userId: approvedByUid,
        userName: approvedByName,
        userRole: 'approver',
        actionType: StaffActionType.saleVoided,
        entityType: 'sale',
        entityId: approval.entityId,
        entityLabel:
            '${approval.entitySnapshot['receiptNumber'] ?? approval.entityId}',
        description: 'Voided sale after approval',
        metadata: {'approvalId': approval.id},
      ),
    );

    await notificationsRepository.createNotification(
      userId: approval.requestedBy,
      type: AppNotificationType.approvalApproved,
      title: 'Void approved',
      body: 'Your request to void the sale was approved.',
      businessId: approval.businessId,
      branchId: branchId,
      entityType: 'sale',
      entityId: approval.entityId,
    );
  }
}

final saleVoidServiceProvider = Provider<SaleVoidService>((ref) {
  return SaleVoidService(
    salesRepository: ref.watch(salesRepositoryProvider),
    teamRepository: ref.watch(teamRepositoryProvider),
    notificationsRepository: ref.watch(notificationsRepositoryProvider),
  );
});
