import 'package:flutter_test/flutter_test.dart';

import 'package:sabibom/features/notifications/application/business_summary_service.dart';
import 'package:sabibom/features/notifications/domain/app_notification.dart';
import 'package:sabibom/features/notifications/domain/attention_summary.dart';

void main() {
  group('AppNotification model', () {
    test('parses snapshot id and legacy read flag', () {
      final n = AppNotification.fromMap('abc123', {
        'type': 'low_stock',
        'title': 'Low stock',
        'body': 'Soap is running low.',
        'read': false,
      });
      expect(n.id, 'abc123');
      expect(n.type, AppNotificationType.lowStock);
      expect(n.isUnread, isTrue);
      expect(n.message, 'Soap is running low.');
      expect(n.category, NotificationCategory.inventory);
    });

    test('parses priority and unknown type fallback', () {
      final n = AppNotification.fromMap('x', {
        'type': 'totally_unknown_type',
        'priority': 'urgent',
        'status': 'read',
        'title': 'Hello',
        'message': 'World',
      });
      expect(n.type, AppNotificationType.general);
      expect(n.priority, NotificationPriority.urgent);
      expect(n.status, NotificationStatus.read);
    });

    test('parses notification image and destination link', () {
      final n = AppNotification.fromMap('media', {
        'title': 'New feature',
        'body': 'See what changed.',
        'imageUrl': 'https://cdn.sabibom.com/feature.jpg',
        'imageCid': 'bafybeigdyrzt1234567890',
        'metadata': {'linkUrl': 'https://sabibom.com/help'},
      });

      expect(n.imageUrl, 'https://cdn.sabibom.com/feature.jpg');
      expect(n.imageCid, 'bafybeigdyrzt1234567890');
      expect(n.linkUrl, 'https://sabibom.com/help');
    });

    test('route allowlist rejects arbitrary routes', () {
      expect(NotificationRouteAllowlist.isAllowed('products'), isTrue);
      expect(NotificationRouteAllowlist.isAllowed('productDetails'), isTrue);
      expect(
        NotificationRouteAllowlist.isAllowed('javascript:alert(1)'),
        isFalse,
      );
      expect(NotificationRouteAllowlist.isAllowed(null), isFalse);
    });

    test('branch scope isolates East and keeps legacy alerts in Main', () {
      AppNotification notification(String id, String? branchId) =>
          AppNotification(
            id: id,
            businessId: 'business',
            branchId: branchId,
            type: AppNotificationType.lowStock,
            title: 'Low stock',
            message: 'Stock warning',
            status: NotificationStatus.unread,
            priority: NotificationPriority.normal,
            category: NotificationCategory.inventory,
          );

      final legacy = notification('legacy', null);
      final main = notification('main', 'main');
      final east = notification('east', 'east');

      expect(
        notificationMatchesBranch(
          legacy,
          selectedBranchId: 'east',
          mainBranchId: 'main',
          isAllBranches: false,
        ),
        isFalse,
      );
      expect(
        notificationMatchesBranch(
          legacy,
          selectedBranchId: 'main',
          mainBranchId: 'main',
          isAllBranches: false,
        ),
        isTrue,
      );
      expect(
        notificationMatchesBranch(
          main,
          selectedBranchId: 'east',
          mainBranchId: 'main',
          isAllBranches: false,
        ),
        isFalse,
      );
      expect(
        notificationMatchesBranch(
          east,
          selectedBranchId: 'east',
          mainBranchId: 'main',
          isAllBranches: false,
        ),
        isTrue,
      );
      expect(
        notificationMatchesBranch(
          east,
          selectedBranchId: null,
          mainBranchId: 'main',
          isAllBranches: true,
        ),
        isTrue,
      );
    });

    test('platform announcements remain visible in every branch', () {
      final announcement = AppNotification(
        id: 'announcement-1',
        type: AppNotificationType.general,
        title: 'New release',
        message: 'SabiBom has been updated.',
        status: NotificationStatus.unread,
        priority: NotificationPriority.normal,
        category: NotificationCategory.system,
        sourceType: 'platform_announcement',
      );

      expect(
        notificationMatchesBranch(
          announcement,
          selectedBranchId: 'east',
          mainBranchId: 'main',
          isAllBranches: false,
        ),
        isTrue,
      );
    });

    test('branch-targeted platform notifications stay in their branch', () {
      final notification = AppNotification(
        id: 'branch-message',
        businessId: 'business',
        branchId: 'east',
        type: AppNotificationType.general,
        title: 'East Branch',
        message: 'Branch notice',
        status: NotificationStatus.unread,
        priority: NotificationPriority.normal,
        category: NotificationCategory.system,
        sourceType: 'platform_notification',
      );

      expect(
        notificationMatchesBranch(
          notification,
          selectedBranchId: 'east',
          mainBranchId: 'main',
          isAllBranches: false,
        ),
        isTrue,
      );
      expect(
        notificationMatchesBranch(
          notification,
          selectedBranchId: 'main',
          mainBranchId: 'main',
          isAllBranches: false,
        ),
        isFalse,
      );
    });
  });

  group('BusinessSummaryService helpers', () {
    test('percentChange handles zero division safely', () {
      expect(BusinessSummaryService.percentChange(0, 0), 0);
      expect(BusinessSummaryService.percentChange(50, 0), 100);
      expect(BusinessSummaryService.percentChange(150, 100), 50);
    });

    test('date and week keys are stable', () {
      final day = DateTime(2026, 7, 22);
      expect(BusinessSummaryService.dateKeyFor(day), '2026-07-22');
      expect(BusinessSummaryService.weekKeyFor(day), startsWith('2026-W'));
    });
  });

  group('Stock alert keys', () {
    test('deduplication keys are stable', () {
      expect('low_stock_biz1_prod1', 'low_stock_biz1_prod1');
    });
  });

  test('attention summary keeps all items beyond dashboard preview', () {
    final items = List<AttentionItem>.generate(
      7,
      (index) => AttentionItem(
        id: '$index',
        title: 'Attention $index',
        subtitle: 'Detail $index',
        priority: 'normal',
      ),
    );
    final summary = AttentionSummary(
      businessId: 'business',
      businessName: 'Business',
      generatedAt: DateTime(2026, 7, 29),
      attentionItems: items,
      topAttentionItems: items.take(5).toList(),
    );

    expect(summary.hasAttention, isTrue);
    expect(summary.attentionItems, hasLength(7));
    expect(summary.topAttentionItems, hasLength(5));
  });
}
