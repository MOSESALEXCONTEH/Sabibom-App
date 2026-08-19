import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../branches/application/current_branch_providers.dart';
import '../../notifications/application/transaction_notification_service.dart';
import '../data/expense_categories_repository.dart';
import '../data/expenses_repository.dart';
import '../data/notifying_expenses_repository.dart';

final expenseCategoriesRepositoryProvider =
    Provider<ExpenseCategoriesRepository>(
      (ref) => FirestoreExpenseCategoriesRepository(),
    );

final expensesRepositoryProvider = Provider<ExpensesRepository>(
  (ref) => NotifyingExpensesRepository(
    FirestoreExpensesRepository(),
    ref.watch(transactionNotificationServiceProvider),
  ),
);

final currentBranchExpensesProvider = Provider<String?>((ref) {
  return ref.watch(currentBranchReadScopeProvider);
});
