import '../application/attention_summary_service.dart';
import '../domain/attention_summary.dart';
import '../../../core/formatting/currency_formatter.dart';

enum SabiAttentionIntent {
  getAttentionSummary,
  listUnreadNotifications,
  listPendingApprovals,
  checkEndOfDay,
  explainDailySummary,
  prepareCustomerReminder,
  markNotificationsRead,
  openNotification,
  unknown,
}

SabiAttentionIntent parseSabiAttentionIntent(String text) {
  final q = text.toLowerCase().trim();
  if (q.isEmpty) return SabiAttentionIntent.unknown;
  // Only broad attention / ops intents — stock, debt, and expiry go to
  // LocalBusinessAnswers / cloud metrics so Sabi answers with records.
  if (q.contains('needs my attention') ||
      q.contains('what needs attention') ||
      q.contains('attention today') ||
      q.contains('what should i focus')) {
    return SabiAttentionIntent.getAttentionSummary;
  }
  if (q.contains('unread notification')) {
    return SabiAttentionIntent.listUnreadNotifications;
  }
  if (q.contains('pending approval') || q.contains('approvals')) {
    return SabiAttentionIntent.listPendingApprovals;
  }
  if (q.contains('end of day') || q.contains('end-of-day')) {
    return SabiAttentionIntent.checkEndOfDay;
  }
  if (q.contains('daily summary') ||
      (q.contains('today') && q.contains('summary'))) {
    return SabiAttentionIntent.explainDailySummary;
  }
  if (q.contains('prepare a reminder') || q.contains('reminder for')) {
    return SabiAttentionIntent.prepareCustomerReminder;
  }
  if (q.contains('mark') && q.contains('notification') && q.contains('read')) {
    return SabiAttentionIntent.markNotificationsRead;
  }
  return SabiAttentionIntent.unknown;
}

bool sabiLooksLikeAttentionQuestion(String text) {
  return parseSabiAttentionIntent(text) != SabiAttentionIntent.unknown;
}

/// Builds a conversational answer from a verified AttentionSummary.
/// Never invents totals — only phrases repository values.
String phraseAttentionSummary(AttentionSummary summary) {
  if (!summary.hasAttention) {
    return 'You’re all caught up for ${summary.businessName}. '
        'I do not see urgent inventory, debt, or approval items right now.';
  }
  final parts = <String>[
    'Here is what needs attention at ${summary.businessName}:',
  ];
  for (final item in summary.topAttentionItems) {
    parts.add('• ${item.title} — ${item.subtitle}');
  }
  if (summary.unreadNotificationCount > 0) {
    parts.add(
      'You also have ${summary.unreadNotificationCount} unread notification'
      '${summary.unreadNotificationCount == 1 ? '' : 's'}.',
    );
  }
  if (summary.customerOutstandingMinor > 0) {
    parts.add(
      'Customer balances outstanding: '
      '${formatCurrency(summary.customerOutstandingMinor / 100)}.',
    );
  }
  if (summary.supplierOutstandingMinor > 0) {
    parts.add(
      'Supplier balances outstanding: '
      '${formatCurrency(summary.supplierOutstandingMinor / 100)}.',
    );
  }
  return parts.join('\n');
}

String buildCustomerReminderDraft({
  required String customerName,
  required String businessName,
  required int balanceMinor,
}) {
  final amount = formatCurrency(balanceMinor / 100);
  return 'Hello $customerName, this is a friendly reminder that your outstanding '
      'balance with $businessName is $amount. Please contact us when convenient. '
      'Thank you.';
}

Future<String> answerAttentionQuestion({
  required String text,
  required String businessId,
  required String businessName,
  String? branchId,
}) async {
  final intent = parseSabiAttentionIntent(text);
  final summary = await AttentionSummaryService().build(
    businessId: businessId,
    businessName: businessName,
    branchId: branchId,
  );

  return switch (intent) {
    SabiAttentionIntent.getAttentionSummary ||
    SabiAttentionIntent.listPendingApprovals ||
    SabiAttentionIntent.listUnreadNotifications ||
    SabiAttentionIntent.checkEndOfDay ||
    SabiAttentionIntent.explainDailySummary => phraseAttentionSummary(summary),
    SabiAttentionIntent.prepareCustomerReminder =>
      'I can prepare an editable reminder after you open the customer. '
          'Reminder drafts are never sent automatically.',
    SabiAttentionIntent.markNotificationsRead =>
      'Open Notifications and tap Mark all read to clear your unread alerts.',
    SabiAttentionIntent.openNotification ||
    SabiAttentionIntent.unknown => phraseAttentionSummary(summary),
  };
}
