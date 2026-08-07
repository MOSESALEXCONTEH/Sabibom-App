import '../domain/sabi_response.dart';

abstract class SabiAssistantService {
  Future<SabiResponse> ask({
    required String businessId,
    required String question,
    required String? branchId,
    required bool isMainBranch,
    required List<Map<String, String>> conversation,
    String? replyLanguage,
  });
}
