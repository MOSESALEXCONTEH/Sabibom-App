import '../../notifications/application/sabi_attention.dart';
import '../domain/sabi_command.dart';
import '../domain/sabi_response.dart';
import 'firebase_sabi_repository.dart';
import 'local_business_answers.dart';
import 'sabi_assistant_service.dart';
import 'sabi_learning_store.dart';
import 'sabi_unanswered_repository.dart';

class CloudSabiAssistantService implements SabiAssistantService {
  CloudSabiAssistantService({
    SabiRepository? repository,
    LocalBusinessAnswers? localAnswers,
    SabiLearningStore? learningStore,
    SabiUnansweredRepository? unansweredRepository,
  }) : _repository = repository ?? SabiRepository(),
       _localAnswers = localAnswers ?? LocalBusinessAnswers(),
       _learning = learningStore ?? SabiLearningStore(),
       _unanswered = unansweredRepository ?? SabiUnansweredRepository();

  final SabiRepository _repository;
  final LocalBusinessAnswers _localAnswers;
  final SabiLearningStore _learning;
  final SabiUnansweredRepository _unanswered;

  @override
  Future<SabiResponse> ask({
    required String businessId,
    required String question,
    required String? branchId,
    required bool isMainBranch,
    required List<Map<String, String>> conversation,
    String? replyLanguage,
  }) async {
    // Deterministic attention answers first — never invent totals via AI.
    final learnedKind = await _learning.suggestKind(
      businessId: businessId,
      question: question,
    );

    // Local Firestore lookups for expiry / stock / debt (works offline from
    // cached rules + avoids waiting on cloud prompt/routing updates).
    final local = await _localAnswers.tryAnswer(
      businessId: businessId,
      question: question,
      forcedKind: learnedKind,
      branchId: branchId,
      isMainBranch: isMainBranch,
    );
    if (local != null) {
      await _learning.rememberVerifiedAsk(
        businessId: businessId,
        question: question,
        kind: learnedKind,
      );
      return SabiResponse(
        text: local,
        verified: true,
        metric: null,
        action: null,
      );
    }

    if (sabiLooksLikeAttentionQuestion(question)) {
      final text = await answerAttentionQuestion(
        text: question,
        businessId: businessId,
        businessName: 'your business',
        branchId: branchId,
      );
      return SabiResponse(
        text: text,
        verified: true,
        metric: null,
        action: null,
      );
    }

    try {
      final answer = await _askAgentWithLegacyFallback(
        businessId: businessId,
        question: question,
        branchId: branchId,
        isMainBranch: isMainBranch,
        conversation: conversation,
        replyLanguage: replyLanguage,
      );
      if (answer.verified) {
        final metricName = answer.metric?['metric']?.toString();
        await _learning.rememberVerifiedAsk(
          businessId: businessId,
          question: question,
          metric: metricName,
        );
      }
      // Unverified asks are persisted by the API into sabi_unanswered.
      return SabiResponse(
        text: answer.answer,
        verified: answer.verified,
        metric: answer.metric,
        action: answer.action,
        sabiAction: answer.sabiAction,
      );
    } catch (_) {
      // Cloud failed — still capture the ask for training review.
      // ignore: unawaited_futures
      _unanswered.record(
        businessId: businessId,
        question: question,
        replyLanguage: replyLanguage,
        source: 'ask_cloud_failed',
      );
      rethrow;
    }
  }

  Future<SabiBusinessAnswer> _askAgentWithLegacyFallback({
    required String businessId,
    required String question,
    required String? branchId,
    required bool isMainBranch,
    required List<Map<String, String>> conversation,
    required String? replyLanguage,
  }) async {
    try {
      return await _repository.askAgent(
        businessId: businessId,
        question: question,
        branchId: branchId,
        conversation: conversation,
      );
    } on SabiException catch (error) {
      if (error.statusCode != 404) rethrow;
      // Allows Flutter and API releases to be deployed independently.
      return _repository.askBusinessQuestion(
        businessId: businessId,
        question: question,
        branchId: branchId,
        isMainBranch: isMainBranch,
        replyLanguage: replyLanguage,
      );
    }
  }
}
