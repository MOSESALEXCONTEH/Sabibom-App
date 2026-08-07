import '../../../core/network/authenticated_api_client.dart';

class AccountDeletionRequest {
  const AccountDeletionRequest({
    required this.requestId,
    required this.scope,
    required this.status,
    required this.reason,
    this.requestedAt,
    this.safeNotes,
  });

  final String requestId;
  final String scope;
  final String status;
  final String reason;
  final DateTime? requestedAt;
  final String? safeNotes;

  factory AccountDeletionRequest.fromMap(Map<String, dynamic> data) =>
      AccountDeletionRequest(
        requestId: data['requestId'] as String? ?? '',
        scope: data['scope'] as String? ?? 'other',
        status: data['status'] as String? ?? 'submitted',
        reason: data['reason'] as String? ?? '',
        requestedAt: DateTime.tryParse(
          data['requestedAt'] as String? ?? '',
        )?.toLocal(),
        safeNotes: data['safeNotes'] as String?,
      );
}

class DeletionRequestsRepository {
  DeletionRequestsRepository({AuthenticatedApiClient? client})
    : _client = client ?? AuthenticatedApiClient();

  final AuthenticatedApiClient _client;

  Future<List<AccountDeletionRequest>> listMine() async {
    final data = await _client.getJson(
      '/api/deletion-requests',
      requireAuth: true,
    );
    final items = data['items'];
    if (items is! List) return const [];
    return items
        .whereType<Map>()
        .map(
          (item) =>
              AccountDeletionRequest.fromMap(Map<String, dynamic>.from(item)),
        )
        .toList(growable: false);
  }

  Future<void> create({
    required String scope,
    required String reason,
    String? businessId,
  }) async {
    await _client.postJson(
      '/api/deletion-requests',
      body: {'scope': scope, 'reason': reason, 'businessId': businessId},
    );
  }
}
