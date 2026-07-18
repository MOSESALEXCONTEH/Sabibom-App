import '../domain/sabi_response.dart';

abstract class SabiAssistantService {
  Future<SabiResponse> ask({
    required String businessId,
    required String question,
  });
}
