import '../../../core/network/api_exception.dart';
import '../../../core/network/authenticated_api_client.dart';
import '../domain/sabi_action.dart';
import '../domain/sabi_command.dart';

/// Sabi API backed by the Vercel Functions deployment.
class SabiRepository {
  SabiRepository({AuthenticatedApiClient? client})
    : _client = client ?? AuthenticatedApiClient();

  final AuthenticatedApiClient _client;

  Future<SabiCommand> parseReceiptCommand({
    required String businessId,
    required String transcript,
    Map<String, dynamic>? draftSummary,
  }) async {
    try {
      final data = await _client.postJson(
        '/api/sabi/parse-receipt',
        body: <String, dynamic>{
          'businessId': businessId,
          'command': transcript,
          'transcript': transcript,
          'currentDraft': ?draftSummary,
        },
      );
      return SabiCommand.fromMap(data);
    } on ApiException catch (error) {
      throw SabiException(
        error.message,
        statusCode: error.statusCode,
        code: error.code,
      );
    }
  }

  /// Parses "add a customer/product" style instructions into a
  /// structured [SabiAction] the app can confirm and execute.
  Future<SabiAction> parseActionCommand({
    required String businessId,
    required String command,
  }) async {
    try {
      final data = await _client.postJson(
        '/api/sabi/parse-action',
        body: <String, dynamic>{'businessId': businessId, 'command': command},
      );
      return SabiAction.fromMap(data);
    } on ApiException catch (error) {
      throw SabiException(
        error.message,
        statusCode: error.statusCode,
        code: error.code,
      );
    }
  }

  Future<SabiBusinessAnswer> askBusinessQuestion({
    required String businessId,
    required String question,
    required String? branchId,
    required bool isMainBranch,
    String? replyLanguage,
  }) async {
    try {
      final data = await _client.postJson(
        '/api/sabi/business-question',
        body: <String, dynamic>{
          'businessId': businessId,
          'question': question,
          'branchId': branchId,
          'isMainBranch': isMainBranch,
          if (replyLanguage != null && replyLanguage.isNotEmpty)
            'replyLanguage': replyLanguage,
        },
      );
      return SabiBusinessAnswer.fromMap(data);
    } on ApiException catch (error) {
      throw SabiException(
        error.message,
        statusCode: error.statusCode,
        code: error.code,
      );
    }
  }

  Future<SabiBusinessAnswer> askAgent({
    required String businessId,
    required String question,
    required String? branchId,
    required List<Map<String, String>> conversation,
  }) async {
    try {
      final data = await _client.postJson(
        '/api/sabi/agent',
        body: <String, dynamic>{
          'businessId': businessId,
          'branchId': branchId,
          'message': question,
          'conversation': conversation,
        },
      );
      return SabiBusinessAnswer.fromMap(data);
    } on ApiException catch (error) {
      throw SabiException(
        error.message,
        statusCode: error.statusCode,
        code: error.code,
      );
    }
  }

  Future<String> composeCustomerMessage({
    required String businessId,
    required String messageType,
    String? notes,
    String? customerName,
    String? businessName,
  }) async {
    try {
      final data = await _client.postJson(
        '/api/sabi/compose-message',
        body: <String, dynamic>{
          'businessId': businessId,
          'messageType': messageType,
          'notes': ?notes,
          'customerName': ?customerName,
          'businessName': ?businessName,
        },
      );
      final message = (data['message'] as String?)?.trim() ?? '';
      if (message.isEmpty) {
        throw const SabiException(
          'Sabi could not draft that message. Please try again.',
        );
      }
      return message;
    } on ApiException catch (error) {
      throw SabiException(
        error.message,
        statusCode: error.statusCode,
        code: error.code,
      );
    }
  }
}

class SabiException implements Exception {
  const SabiException(this.message, {this.statusCode, this.code});
  final String message;
  final int? statusCode;
  final String? code;

  @override
  String toString() => message;
}
