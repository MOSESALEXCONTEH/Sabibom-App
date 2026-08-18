import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../core/network/api_config.dart';
import '../domain/runtime_configuration.dart';

class RuntimeConfigurationRepository {
  RuntimeConfigurationRepository({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;

  Future<RuntimeConfiguration> fetch() async {
    final response = await _client
        .get(ApiConfig.uri('/api/runtime-config'))
        .timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) {
      throw StateError('Runtime configuration is unavailable.');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map || decoded['success'] != true) {
      throw const FormatException('Invalid runtime configuration.');
    }
    final payload = decoded['data'];
    if (payload is! Map) {
      throw const FormatException('Missing runtime configuration.');
    }
    return RuntimeConfiguration.fromMap(Map<String, dynamic>.from(payload));
  }
}

final runtimeConfigurationRepositoryProvider =
    Provider<RuntimeConfigurationRepository>((ref) {
      final repository = RuntimeConfigurationRepository();
      ref.onDispose(repository._client.close);
      return repository;
    });

final runtimeConfigurationProvider = StreamProvider<RuntimeConfiguration>((
  ref,
) async* {
  final repository = ref.watch(runtimeConfigurationRepositoryProvider);
  final random = Random();
  while (true) {
    try {
      yield await repository.fetch();
    } catch (_) {
      // API middleware still enforces API-wide maintenance if this check fails.
    }
    await Future<void>.delayed(Duration(seconds: 45 + random.nextInt(16)));
  }
});
