import 'package:connectivity_plus/connectivity_plus.dart';

/// Exposes the device connectivity stream to domain and presentation layers.
class ConnectivityService {
  /// Streams current connectivity results.
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      Connectivity().onConnectivityChanged;

  /// Fetches the current connectivity state.
  Future<List<ConnectivityResult>> check() =>
      Connectivity().checkConnectivity();
}
