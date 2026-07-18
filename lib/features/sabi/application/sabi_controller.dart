import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/sabi_message.dart';
import 'sabi_providers.dart';

class SabiAssistantState {
  const SabiAssistantState({
    this.messages = const <SabiMessage>[],
    this.isLoading = false,
    this.errorMessage,
  });

  final List<SabiMessage> messages;
  final bool isLoading;
  final String? errorMessage;

  SabiAssistantState copyWith({
    List<SabiMessage>? messages,
    bool? isLoading,
    String? errorMessage,
    bool clearError = false,
  }) {
    return SabiAssistantState(
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}

class SabiAssistantController extends Notifier<SabiAssistantState> {
  @override
  SabiAssistantState build() => const SabiAssistantState();

  Future<void> ask({
    required String businessId,
    required String question,
  }) async {
    final trimmedQuestion = question.trim();
    if (state.isLoading || trimmedQuestion.isEmpty) return;
    if (businessId.trim().isEmpty) {
      state = state.copyWith(
        errorMessage: 'Set up your business first so Sabi can understand it.',
      );
      return;
    }

    final userMessage = SabiMessage(
      id: 'user-${DateTime.now().microsecondsSinceEpoch}',
      author: SabiMessageAuthor.user,
      text: trimmedQuestion,
      createdAt: DateTime.now(),
    );
    state = state.copyWith(
      messages: <SabiMessage>[...state.messages, userMessage],
      isLoading: true,
      clearError: true,
    );

    try {
      final response = await ref
          .read(sabiAssistantServiceProvider)
          .ask(businessId: businessId, question: trimmedQuestion);
      final assistantMessage = SabiMessage(
        id: 'assistant-${DateTime.now().microsecondsSinceEpoch}',
        author: SabiMessageAuthor.assistant,
        text: response.text,
        createdAt: DateTime.now(),
      );
      state = state.copyWith(
        messages: <SabiMessage>[...state.messages, assistantMessage],
        isLoading: false,
      );
    } catch (_) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Sabi is temporarily unavailable. Please try again.',
      );
    }
  }
}

final sabiAssistantControllerProvider =
    NotifierProvider<SabiAssistantController, SabiAssistantState>(
      SabiAssistantController.new,
    );
