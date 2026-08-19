import '../../notifications/application/transaction_notification_service.dart';
import '../domain/expense.dart';
import 'expenses_repository.dart';

class NotifyingExpensesRepository implements ExpensesRepository {
  const NotifyingExpensesRepository(this._delegate, this._notifications);

  final ExpensesRepository _delegate;
  final TransactionNotificationService _notifications;

  @override
  Future<String> createExpense(
    String businessId,
    ExpenseDraft draft, {
    String? branchId,
    bool queueWhenOffline = false,
  }) async {
    final id = await _delegate.createExpense(
      businessId,
      draft,
      branchId: branchId,
      queueWhenOffline: queueWhenOffline,
    );
    await _notifications.notify(
      RecordedTransactionNotification(
        type: RecordedTransactionType.expense,
        entityId: id,
        reference: draft.description,
        pendingSync: queueWhenOffline,
      ),
    );
    return id;
  }

  @override
  Future<Expense?> getExpense(
    String businessId,
    String expenseId, {
    String? branchId,
  }) => _delegate.getExpense(businessId, expenseId, branchId: branchId);

  @override
  Future<int> totalActiveMinor(
    String businessId, {
    DateTime? start,
    DateTime? end,
    String? branchId,
  }) => _delegate.totalActiveMinor(
    businessId,
    start: start,
    end: end,
    branchId: branchId,
  );

  @override
  Future<void> updateExpense(
    String businessId,
    String expenseId,
    ExpenseDraft draft, {
    String? branchId,
  }) =>
      _delegate.updateExpense(businessId, expenseId, draft, branchId: branchId);

  @override
  Future<void> voidExpense(
    String businessId,
    String expenseId, {
    required String reason,
    String? branchId,
  }) => _delegate.voidExpense(
    businessId,
    expenseId,
    reason: reason,
    branchId: branchId,
  );

  @override
  Stream<List<Expense>> watchExpenses(
    String businessId, {
    DateTime? start,
    DateTime? end,
    String? branchId,
    int limit = 100,
  }) => _delegate.watchExpenses(
    businessId,
    start: start,
    end: end,
    branchId: branchId,
    limit: limit,
  );
}
