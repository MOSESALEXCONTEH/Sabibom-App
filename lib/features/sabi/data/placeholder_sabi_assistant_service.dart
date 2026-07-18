import '../domain/sabi_response.dart';
import 'sabi_assistant_service.dart';

class PlaceholderSabiAssistantService implements SabiAssistantService {
  @override
  Future<SabiResponse> ask({
    required String businessId,
    required String question,
  }) async {
    return const SabiResponse(
      text:
          'Sabi will use your sales, stock, customer and expense data to answer this question once the assistant service is connected.',
    );
  }
}
