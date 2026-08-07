import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../branches/application/current_branch_providers.dart';
import '../data/expense_categories_repository.dart';
import '../data/expenses_repository.dart';

final expenseCategoriesRepositoryProvider =
    Provider<ExpenseCategoriesRepository>(
      (ref) => FirestoreExpenseCategoriesRepository(),
    );

final expensesRepositoryProvider = Provider<ExpensesRepository>(
  (ref) => FirestoreExpensesRepository(),
);

final currentBranchExpensesProvider = Provider<String?>((ref) {
  return ref.watch(currentBranchReadScopeProvider);
});
