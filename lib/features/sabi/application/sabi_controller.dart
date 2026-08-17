import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../customers/application/customers_providers.dart';
import '../../customers/data/customers_repository.dart';
import '../../branches/application/current_branch_providers.dart';
import '../../expenses/application/expenses_providers.dart';
import '../../expenses/domain/expense.dart';
import '../../expenses/domain/expense_category.dart';
import '../../dashboard/application/dashboard_providers.dart';
import '../../products/application/products_providers.dart';
import '../../products/data/products_repository.dart';
import '../../products/domain/product.dart';
import '../../suppliers/application/suppliers_providers.dart';
import '../../suppliers/data/suppliers_repository.dart';
import '../../suppliers/domain/supplier.dart';
import '../data/firebase_sabi_repository.dart';
import '../domain/sabi_action.dart';
import '../domain/sabi_intent.dart' as sabi_intents;
import '../domain/sabi_message.dart';
import '../services/sabi_tts_service.dart';
import 'sabi_providers.dart';

class SabiAssistantState {
  const SabiAssistantState({
    this.messages = const <SabiMessage>[],
    this.isLoading = false,
    this.isHistoryReady = false,
    this.errorMessage,
    this.pendingAction,
    this.pendingSabiAction,
    this.pendingActionFromVoice = false,
    this.pendingClarificationIntent,
  });

  final List<SabiMessage> messages;
  final bool isLoading;
  final bool isHistoryReady;
  final String? errorMessage;
  final String? pendingAction;

  /// Structured action (add customer / add product) awaiting confirmation.
  final SabiAction? pendingSabiAction;
  final bool pendingActionFromVoice;
  final String? pendingClarificationIntent;

  SabiAssistantState copyWith({
    List<SabiMessage>? messages,
    bool? isLoading,
    bool? isHistoryReady,
    String? errorMessage,
    bool clearError = false,
    String? pendingAction,
    bool clearPendingAction = false,
    SabiAction? pendingSabiAction,
    bool clearPendingSabiAction = false,
    bool? pendingActionFromVoice,
    String? pendingClarificationIntent,
    bool clearPendingClarification = false,
  }) {
    return SabiAssistantState(
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
      isHistoryReady: isHistoryReady ?? this.isHistoryReady,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
      pendingAction: clearPendingAction
          ? null
          : pendingAction ?? this.pendingAction,
      pendingSabiAction: clearPendingSabiAction
          ? null
          : pendingSabiAction ?? this.pendingSabiAction,
      pendingActionFromVoice:
          pendingActionFromVoice ?? this.pendingActionFromVoice,
      pendingClarificationIntent: clearPendingClarification
          ? null
          : pendingClarificationIntent ?? this.pendingClarificationIntent,
    );
  }
}

class SabiAssistantController extends Notifier<SabiAssistantState> {
  @override
  SabiAssistantState build() => const SabiAssistantState(isHistoryReady: true);

  Future<void> clearHistory() async {
    startFreshSession();
  }

  void startFreshSession() {
    state = state.copyWith(
      messages: const <SabiMessage>[],
      isHistoryReady: true,
      clearPendingAction: true,
      clearPendingSabiAction: true,
      clearPendingClarification: true,
      clearError: true,
      isLoading: false,
    );
  }

  void editMessage(String messageId) {
    final index = state.messages.indexWhere(
      (message) =>
          message.id == messageId && message.author == SabiMessageAuthor.user,
    );
    if (index < 0) return;
    state = state.copyWith(
      messages: state.messages.take(index).toList(growable: false),
      clearPendingAction: true,
      clearPendingSabiAction: true,
      clearPendingClarification: true,
      clearError: true,
      isLoading: false,
    );
  }

  Future<void> ask({
    required String businessId,
    required String question,
    bool speakReply = false,
    String? replyLanguage,
  }) async {
    final trimmedQuestion = question.trim();
    if (state.isLoading || trimmedQuestion.isEmpty) return;
    if (businessId.trim().isEmpty) {
      state = state.copyWith(
        errorMessage: 'Set up your business first so Sabi can understand it.',
      );
      return;
    }

    _addUserMessage(trimmedQuestion);

    try {
      final branch = ref.read(currentBranchProvider).asData?.value;
      final resolvedQuestion = sabi_intents.resolveSabiFollowUp(
        trimmedQuestion,
        state.messages.reversed
            .skip(1)
            .where((message) => message.author == SabiMessageAuthor.user)
            .map((message) => message.text),
      );
      final response = await ref
          .read(sabiAssistantServiceProvider)
          .ask(
            businessId: businessId,
            question: resolvedQuestion,
            branchId: branch?.branchId,
            isMainBranch:
                branch != null &&
                !branch.isAllBranchesMode &&
                branch.selectedBranch.branchId == branch.mainBranch.branchId,
            conversation: _conversationForAgent(),
            replyLanguage: replyLanguage,
          );
      final metric = response.metric;
      final metricLine = metric == null
          ? ''
          : '\n\n'
                'Value: ${metric['value'] ?? '-'} '
                '${metric['currencySymbol'] ?? ''}\n'
                'Period: ${metric['period'] ?? '-'}\n'
                'Source: ${metric['source'] ?? '-'}\n'
                'Updated: ${metric['lastUpdatedIso'] ?? '-'}';
      _addAssistantMessage('${response.text}$metricLine');
      state = state.copyWith(
        isLoading: false,
        pendingAction: response.action,
        pendingSabiAction: response.sabiAction,
      );
      if (speakReply) {
        await ref.read(sabiTtsServiceProvider).speak(response.text);
      }
    } on SabiException catch (error) {
      state = state.copyWith(isLoading: false, errorMessage: error.message);
    } catch (_) {
      state = state.copyWith(
        isLoading: false,
        errorMessage:
            'Sabi is temporarily unavailable. You can continue the sale manually.',
      );
    }
  }

  /// Parses an "add customer" / "add product" instruction and stages it
  /// for confirmation.
  Future<void> parseAction({
    required String businessId,
    required String instruction,
    bool fromVoice = false,
  }) async {
    final trimmed = instruction.trim();
    if (state.isLoading || trimmed.isEmpty) return;
    if (businessId.trim().isEmpty) {
      state = state.copyWith(
        errorMessage: 'Set up your business first so Sabi can understand it.',
      );
      return;
    }

    _addUserMessage(trimmed);

    try {
      var pendingIntent = state.pendingClarificationIntent;
      if (pendingIntent != null &&
          RegExp(
            r'^(cancel|stop|never mind|nevermind|no)$',
            caseSensitive: false,
          ).hasMatch(trimmed)) {
        _addAssistantMessage('Okay, I cancelled that request.');
        state = state.copyWith(
          isLoading: false,
          clearPendingClarification: true,
        );
        return;
      }
      final explicitIntent = sabi_intents.sabiCreationIntentFor(trimmed);
      final clarification = sabi_intents.sabiClarificationFor(trimmed);
      if (pendingIntent != null &&
          explicitIntent != null &&
          explicitIntent != pendingIntent) {
        pendingIntent = null;
        state = state.copyWith(clearPendingClarification: true);
      }
      if (pendingIntent == null) {
        if (clarification != null) {
          _addAssistantMessage(clarification.question);
          state = state.copyWith(
            isLoading: false,
            pendingClarificationIntent: clarification.intent,
          );
          if (fromVoice) {
            await ref
                .read(sabiTtsServiceProvider)
                .speak(clarification.question);
          }
          return;
        }
      }
      final command = pendingIntent == null
          ? trimmed
          : sabi_intents.sabiCommandWithClarificationContext(
              intent: pendingIntent,
              answer: trimmed,
            );
      state = state.copyWith(clearPendingClarification: true);
      final localAction = _actionFromClarification(pendingIntent, trimmed);
      final action =
          localAction ??
          await ref
              .read(sabiRepositoryProvider)
              .parseActionCommand(
                businessId: businessId,
                command: sabi_intents.normalizeSabiInput(command),
              );

      if (action.clarifyingQuestion?.trim().isNotEmpty == true) {
        _addAssistantMessage(action.clarifyingQuestion!);
        state = state.copyWith(isLoading: false);
        if (fromVoice) {
          await ref
              .read(sabiTtsServiceProvider)
              .speak(action.clarifyingQuestion!);
        }
        return;
      }

      if (action.isAskIntent) {
        // Question intents from parse-action should use the ask pipeline.
        state = state.copyWith(isLoading: false);
        // Remove the user message we just added so ask() can re-add cleanly,
        // or call the service directly without duplicating the user bubble.
        await _answerAskAfterParse(
          businessId: businessId,
          question: trimmed,
          speakReply: fromVoice,
        );
        return;
      }

      if (action.isAddCustomer ||
          action.isAddProduct ||
          action.canConfirmExpense ||
          action.canConfirmSupplier) {
        final reply = action.reply.trim().isEmpty
            ? 'I prepared that for you. Please review and confirm below.'
            : action.reply;
        _addAssistantMessage(reply);
        state = state.copyWith(
          isLoading: false,
          pendingSabiAction: action,
          pendingActionFromVoice: fromVoice,
        );
        if (fromVoice) {
          await ref.read(sabiTtsServiceProvider).speak(reply);
        }
        return;
      }

      if (action.isCreateReceipt) {
        _addAssistantMessage(
          'Let\'s draft that receipt. I\'m opening the sale draft for you.',
        );
        state = state.copyWith(
          isLoading: false,
          pendingAction: 'open_sale_draft',
        );
        return;
      }

      if (action.isCreateExpense) {
        final reply = action.reply.trim().isEmpty
            ? 'I prepared an expense draft. Opening Add Expense so you can finish it.'
            : action.reply;
        _addAssistantMessage(reply);
        state = state.copyWith(
          isLoading: false,
          pendingAction: 'open_expense_draft',
          pendingSabiAction: action,
        );
        if (fromVoice) {
          await ref.read(sabiTtsServiceProvider).speak(reply);
        }
        return;
      }

      if (action.isCreateSupplier) {
        final reply = action.reply.trim().isEmpty
            ? 'I prepared a supplier draft. Opening Add Supplier so you can finish it.'
            : action.reply;
        _addAssistantMessage(reply);
        state = state.copyWith(
          isLoading: false,
          pendingAction: 'open_supplier_draft',
          pendingSabiAction: action,
        );
        if (fromVoice) {
          await ref.read(sabiTtsServiceProvider).speak(reply);
        }
        return;
      }

      if (action.isCreatePurchase) {
        final reply = action.reply.trim().isEmpty
            ? 'I prepared a purchase. Opening New Purchase so you can review and complete it.'
            : action.reply;
        _addAssistantMessage(reply);
        state = state.copyWith(
          isLoading: false,
          pendingAction: 'open_purchase_draft',
          pendingSabiAction: action,
        );
        if (fromVoice) {
          await ref.read(sabiTtsServiceProvider).speak(reply);
        }
        return;
      }

      const fallback =
          'I couldn\'t work out what to add. Try something like: '
          '"Add a customer called Aminata, phone 076 123 456", '
          '"Record 200 Leones for transport", or '
          '"Add Mohamed Trading as a supplier".';
      _addAssistantMessage(fallback);
      state = state.copyWith(isLoading: false);
      if (fromVoice) {
        await ref.read(sabiTtsServiceProvider).speak(fallback);
      }
    } on SabiException catch (error) {
      state = state.copyWith(isLoading: false, errorMessage: error.message);
    } catch (_) {
      state = state.copyWith(
        isLoading: false,
        errorMessage:
            'Sabi is temporarily unavailable. You can add it manually instead.',
      );
    }
  }

  /// Answers a metric question after parse-action returned ask_*.
  Future<void> _answerAskAfterParse({
    required String businessId,
    required String question,
    bool speakReply = false,
  }) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final branch = ref.read(currentBranchProvider).asData?.value;
      final response = await ref
          .read(sabiAssistantServiceProvider)
          .ask(
            businessId: businessId,
            question: question,
            branchId: branch?.branchId,
            isMainBranch:
                branch != null &&
                !branch.isAllBranchesMode &&
                branch.selectedBranch.branchId == branch.mainBranch.branchId,
            conversation: _conversationForAgent(),
          );
      final metric = response.metric;
      final metricLine = metric == null
          ? ''
          : '\n\n'
                'Value: ${metric['value'] ?? '-'} '
                '${metric['currencySymbol'] ?? ''}\n'
                'Period: ${metric['period'] ?? '-'}\n'
                'Source: ${metric['source'] ?? '-'}\n'
                'Updated: ${metric['lastUpdatedIso'] ?? '-'}';
      _addAssistantMessage('${response.text}$metricLine');
      state = state.copyWith(
        isLoading: false,
        pendingAction: response.action,
        pendingSabiAction: response.sabiAction,
      );
      if (speakReply) {
        await ref.read(sabiTtsServiceProvider).speak(response.text);
      }
    } on SabiException catch (error) {
      state = state.copyWith(isLoading: false, errorMessage: error.message);
    } catch (_) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Sabi is temporarily unavailable. Please try again.',
      );
    }
  }

  /// Executes the staged action after the merchant confirms it.
  Future<void> confirmPendingSabiAction({required String businessId}) async {
    final action = state.pendingSabiAction;
    if (action == null || state.isLoading) return;
    final speak = state.pendingActionFromVoice;
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      String confirmation;
      if (action.isAddCustomer) {
        confirmation = await _createCustomer(businessId, action.customer!);
      } else if (action.isAddProduct) {
        confirmation = await _createProduct(businessId, action.product!);
      } else if (action.canConfirmExpense) {
        confirmation = await _createExpense(businessId, action.expense!);
      } else if (action.canConfirmSupplier) {
        confirmation = await _createSupplier(businessId, action.supplier!);
      } else {
        state = state.copyWith(isLoading: false, clearPendingSabiAction: true);
        return;
      }
      _addAssistantMessage(confirmation);
      state = state.copyWith(
        isLoading: false,
        clearPendingSabiAction: true,
        pendingActionFromVoice: false,
      );
      if (speak) {
        await ref.read(sabiTtsServiceProvider).speak(confirmation);
      }
    } on DuplicateCustomerException catch (error) {
      final message =
          'A customer with this phone number already exists: '
          '${error.existing.name}. I did not add a duplicate.';
      _addAssistantMessage(message);
      state = state.copyWith(
        isLoading: false,
        clearPendingSabiAction: true,
        pendingActionFromVoice: false,
      );
      if (speak) {
        await ref.read(sabiTtsServiceProvider).speak(message);
      }
    } on DuplicateSupplierException catch (error) {
      final message =
          'A supplier with this phone number already exists: '
          '${error.existing.name}. I did not add a duplicate.';
      _addAssistantMessage(message);
      state = state.copyWith(
        isLoading: false,
        clearPendingSabiAction: true,
        pendingActionFromVoice: false,
      );
      if (speak) {
        await ref.read(sabiTtsServiceProvider).speak(message);
      }
    } on CustomerException catch (error) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: error.friendlyMessage,
      );
    } on ProductException catch (error) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: error.friendlyMessage,
      );
    } on ExpenseException catch (error) {
      state = state.copyWith(isLoading: false, errorMessage: error.userMessage);
    } on SupplierException catch (error) {
      state = state.copyWith(isLoading: false, errorMessage: error.userMessage);
    } on SabiException catch (error) {
      state = state.copyWith(isLoading: false, errorMessage: error.message);
    } catch (_) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Could not save that. Please try again.',
      );
    }
  }

  void cancelPendingSabiAction() {
    if (state.pendingSabiAction == null) return;
    _addAssistantMessage('Okay, I cancelled that.');
    state = state.copyWith(
      isLoading: false,
      clearPendingSabiAction: true,
      pendingActionFromVoice: false,
    );
  }

  /// Clears a staged action without posting a cancel message (form handoff).
  void cancelPendingSabiActionQuietly() {
    if (state.pendingSabiAction == null) return;
    state = state.copyWith(
      clearPendingSabiAction: true,
      pendingActionFromVoice: false,
    );
  }

  void cancelPendingClarificationQuietly() {
    if (state.pendingClarificationIntent == null) return;
    state = state.copyWith(clearPendingClarification: true);
  }

  SabiAction? _actionFromClarification(String? intent, String answer) {
    if (intent == 'add_customer') {
      final contact = sabi_intents.parseSabiContactInput(answer);
      if (contact == null) return null;
      return SabiAction(
        intent: intent!,
        confidence: 1,
        reply: 'I prepared this customer. Please review and confirm.',
        requiresConfirmation: true,
        warnings: const <String>[],
        customer: SabiCustomerDetails(
          name: contact.name,
          phone: contact.phone,
          email: contact.email,
        ),
      );
    }
    if (intent == 'create_supplier') {
      final contact = sabi_intents.parseSabiContactInput(answer);
      if (contact == null) return null;
      return SabiAction(
        intent: intent!,
        confidence: 1,
        reply: 'I prepared this supplier. Please review and confirm.',
        requiresConfirmation: true,
        warnings: const <String>[],
        supplier: SabiSupplierDetails(name: contact.name, phone: contact.phone),
      );
    }
    if (intent == 'create_receipt') {
      return const SabiAction(
        intent: 'create_receipt',
        confidence: 1,
        reply: 'I will open a sale draft for you to review.',
        requiresConfirmation: true,
        warnings: <String>[],
      );
    }
    if (intent == 'create_purchase') {
      return const SabiAction(
        intent: 'create_purchase',
        confidence: 1,
        reply: 'I will open a purchase draft for you to review.',
        requiresConfirmation: true,
        warnings: <String>[],
      );
    }
    return null;
  }

  Future<String> _createExpense(
    String businessId,
    SabiExpenseDetails details,
  ) async {
    final branchId = _requireWritableBranch();
    final amountMinor = details.amountMinor ?? 0;
    if (amountMinor <= 0) {
      throw const ExpenseException(
        'failed-precondition',
        message: 'I still need the expense amount before I can save it.',
      );
    }
    final categoriesRepo = ref.read(expenseCategoriesRepositoryProvider);
    await categoriesRepo.ensureDefaults(businessId);
    final categories = await categoriesRepo.watchCategories(businessId).first;
    final wanted = (details.categoryName ?? '').trim().toLowerCase();
    ExpenseCategory? category;
    if (wanted.isNotEmpty) {
      for (final c in categories) {
        if (c.name.toLowerCase() == wanted ||
            c.name.toLowerCase().contains(wanted) ||
            wanted.contains(c.name.toLowerCase())) {
          category = c;
          break;
        }
      }
      if (category == null &&
          (wanted.contains('transport') || wanted.contains('fuel'))) {
        for (final c in categories) {
          if (c.name.toLowerCase().contains('transport')) {
            category = c;
            break;
          }
        }
      }
    }
    if (category == null) {
      for (final c in categories) {
        if (c.name.toLowerCase() == 'other') {
          category = c;
          break;
        }
      }
    }
    category ??= categories.isEmpty ? null : categories.first;
    if (category == null) {
      throw const ExpenseException(
        'failed-precondition',
        message: 'No expense categories found. Add a category first.',
      );
    }
    final description = (details.description?.trim().isNotEmpty == true)
        ? details.description!.trim()
        : (details.categoryName?.trim().isNotEmpty == true
              ? details.categoryName!.trim()
              : 'Expense');
    await ref
        .read(expensesRepositoryProvider)
        .createExpense(
          businessId,
          ExpenseDraft(
            amountMinor: amountMinor,
            categoryId: category.id,
            categoryName: category.name,
            description: description,
            paymentMethod: ExpensePaymentMethod.fromStorage(
              details.paymentMethod ?? 'cash',
            ),
            expenseDate: DateTime.now(),
          ),
          branchId: branchId,
        );
    final activeBusiness = ref.read(activeBusinessProvider).asData?.value;
    final currencySymbol = activeBusiness is ActiveBusinessData
        ? activeBusiness.business.currency.symbol
        : null;
    return 'Done! I recorded an expense of ${currencySymbol ?? 'Le'} '
        '${(amountMinor / 100).toStringAsFixed(2)} for $description '
        '(${category.name}).';
  }

  Future<String> _createSupplier(
    String businessId,
    SabiSupplierDetails details,
  ) async {
    final branchId = _requireWritableBranch();
    final name = details.name?.trim() ?? '';
    if (name.length < 2) {
      throw const SupplierException(
        'failed-precondition',
        message: 'I still need the supplier name before I can add them.',
      );
    }
    await ref
        .read(suppliersRepositoryProvider)
        .createSupplier(
          businessId,
          SupplierDraft(name: name, phone: details.phone),
          branchId: branchId,
        );
    final phonePart = details.phone == null ? '' : ' (${details.phone})';
    return 'Done! I added $name$phonePart to your suppliers.';
  }

  Future<String> _createCustomer(
    String businessId,
    SabiCustomerDetails details,
  ) async {
    final branchId = _requireWritableBranch();
    if (details.name.trim().isEmpty) {
      throw const CustomerException(
        'invalid-argument',
        message: 'I still need the customer\'s name before I can add them.',
      );
    }
    await ref
        .read(customersRepositoryProvider)
        .createCustomer(
          businessId,
          CustomerDraft(
            name: details.name.trim(),
            phone: details.phone,
            email: details.email,
            address: details.address,
            notes: details.notes,
          ),
          branchId: branchId,
        );
    final phonePart = details.phone == null ? '' : ' (${details.phone})';
    return 'Done! I added ${details.name}$phonePart to your customers.';
  }

  Future<String> _createProduct(
    String businessId,
    SabiProductDetails details,
  ) async {
    final branchId = _requireWritableBranch();
    if (details.name.trim().isEmpty) {
      throw const ProductException(
        'invalid-argument',
        message: 'I still need the product name before I can add it.',
      );
    }
    if (details.sellingPriceMinor == null) {
      throw ProductException(
        'invalid-argument',
        message:
            'I still need the selling price. Try: "Add product '
            '${details.name} at 50 Leones".',
      );
    }
    final trackStock = details.quantity != null;
    await ref
        .read(productsRepositoryProvider)
        .createProduct(
          businessId,
          ProductDraft(
            name: details.name.trim(),
            sellingPriceMinor: details.sellingPriceMinor!,
            costPriceMinor: details.costPriceMinor ?? 0,
            trackStock: trackStock,
            quantity: details.quantity ?? 0,
            lowStockThreshold: details.lowStockThreshold ?? 0,
            unit: _normalizeUnit(details.unit),
            status: ProductStatus.active,
            categoryName: details.categoryName,
            description: details.description,
          ),
          branchId: branchId,
        );
    final stockPart = details.quantity == null
        ? ''
        : ' with ${_qtyLabel(details.quantity!)} in stock';
    return 'Done! I added ${details.name} to your products$stockPart.';
  }

  String _normalizeUnit(String? spoken) {
    if (spoken == null || spoken.trim().isEmpty) return 'Piece';
    final lower = spoken.trim().toLowerCase();
    for (final unit in productUnits) {
      if (unit.toLowerCase() == lower ||
          '${unit.toLowerCase()}s' == lower ||
          unit.toLowerCase() == '${lower}s') {
        return unit;
      }
    }
    return 'Other';
  }

  String _requireWritableBranch() {
    final branchId = ref.read(currentWritableBranchIdProvider)?.trim();
    if (branchId == null || branchId.isEmpty) {
      throw const SabiException(branchWriteBlockedMessage);
    }
    return branchId;
  }

  List<Map<String, String>> _conversationForAgent() {
    final prior = state.messages.isEmpty
        ? const <SabiMessage>[]
        : state.messages.take(state.messages.length - 1).toList();
    return prior
        .skip(prior.length > 12 ? prior.length - 12 : 0)
        .map(
          (message) => <String, String>{
            'role': message.author == SabiMessageAuthor.user
                ? 'user'
                : 'assistant',
            'content': message.text,
          },
        )
        .toList(growable: false);
  }

  String _qtyLabel(double value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toStringAsFixed(2);

  void _addUserMessage(String text) {
    final userMessage = SabiMessage(
      id: 'user-${DateTime.now().microsecondsSinceEpoch}',
      author: SabiMessageAuthor.user,
      text: text,
      createdAt: DateTime.now(),
    );
    state = state.copyWith(
      messages: <SabiMessage>[...state.messages, userMessage],
      isLoading: true,
      clearError: true,
      clearPendingAction: true,
      clearPendingSabiAction: true,
    );
  }

  void _addAssistantMessage(String text) {
    final assistantMessage = SabiMessage(
      id: 'assistant-${DateTime.now().microsecondsSinceEpoch}',
      author: SabiMessageAuthor.assistant,
      text: text,
      createdAt: DateTime.now(),
    );
    state = state.copyWith(
      messages: <SabiMessage>[...state.messages, assistantMessage],
    );
  }

  void clearPendingAction() {
    state = state.copyWith(clearPendingAction: true);
  }
}

final sabiAssistantControllerProvider =
    NotifierProvider<SabiAssistantController, SabiAssistantState>(
      SabiAssistantController.new,
    );
