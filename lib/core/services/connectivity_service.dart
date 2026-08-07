import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Exposes the device connectivity stream to domain and presentation layers.
class ConnectivityService {
  /// Streams current connectivity results.
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      Connectivity().onConnectivityChanged;

  /// Fetches the current connectivity state.
  Future<List<ConnectivityResult>> check() =>
      Connectivity().checkConnectivity();
}

final connectivityServiceProvider = Provider<ConnectivityService>(
  (ref) => ConnectivityService(),
);

final isOnlineProvider = StreamProvider<bool>((ref) async* {
  final service = ref.watch(connectivityServiceProvider);
  bool hasConnection(List<ConnectivityResult> results) =>
      results.any((result) => result != ConnectivityResult.none);

  yield hasConnection(await service.check());
  yield* service.onConnectivityChanged.map(hasConnection).distinct();
});
