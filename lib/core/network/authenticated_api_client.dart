import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_performance/firebase_performance.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import 'api_config.dart';
import 'api_exception.dart';

class AuthenticatedApiClient {
  AuthenticatedApiClient({
    FirebaseAuth? auth,
    http.Client? httpClient,
    Future<PackageInfo> Function()? packageInfoLoader,
  })
    : _auth = auth ?? FirebaseAuth.instance,
      _http = httpClient ?? http.Client(),
      _packageInfoLoader = packageInfoLoader ?? PackageInfo.fromPlatform;

  final FirebaseAuth _auth;
  final http.Client _http;
  final Future<PackageInfo> Function() _packageInfoLoader;
  Future<PackageInfo>? _packageInfo;

  Future<Map<String, String>> _appMetadataHeaders() async {
    try {
      final package = await (_packageInfo ??= _packageInfoLoader());
      return <String, String>{
        'X-SabiBom-Platform': defaultTargetPlatform.name,
        'X-SabiBom-App-Version': package.version,
        'X-SabiBom-App-Build': package.buildNumber,
      };
    } catch (_) {
      return const <String, String>{};
    }
  }

  Future<Map<String, dynamic>> postJson(
    String path, {
    required Map<String, dynamic> body,
    Duration timeout = const Duration(seconds: 40),
  }) async {
    return _send(
      method: 'POST',
      path: path,
      body: body,
      timeout: timeout,
      allowRefreshRetry: true,
    );
  }

  Future<Map<String, dynamic>> getJson(
    String path, {
    Duration timeout = const Duration(seconds: 20),
    bool requireAuth = false,
  }) async {
    return _send(
      method: 'GET',
      path: path,
      timeout: timeout,
      allowRefreshRetry: requireAuth,
      requireAuth: requireAuth,
    );
  }

  Future<Map<String, dynamic>> _send({
    required String method,
    required String path,
    Map<String, dynamic>? body,
    required Duration timeout,
    required bool allowRefreshRetry,
    bool requireAuth = true,
  }) async {
    Trace? trace;
    if (kReleaseMode) {
      trace = FirebasePerformance.instance.newTrace(
        'authenticated_api_request',
      );
      trace.putAttribute('method', method);
      await trace.start();
    }

    Future<http.Response> execute({bool forceRefresh = false}) async {
      final headers = <String, String>{
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };
      headers.addAll(await _appMetadataHeaders());
      try {
        final appCheckToken = await FirebaseAppCheck.instance.getToken();
        if (appCheckToken != null && appCheckToken.isNotEmpty) {
          headers['X-Firebase-AppCheck'] = appCheckToken;
        }
      } catch (_) {
        // The API decides whether App Check is currently enforced.
      }

      if (requireAuth) {
        final user = _auth.currentUser;
        if (user == null) {
          throw const ApiException(
            'Your session expired. Please sign in again.',
            statusCode: 401,
            code: 'unauthenticated',
          );
        }
        final token = await user.getIdToken(forceRefresh);
        if (token == null || token.isEmpty) {
          throw const ApiException(
            'Your session expired. Please sign in again.',
            statusCode: 401,
            code: 'unauthenticated',
          );
        }
        headers['Authorization'] = 'Bearer $token';
      }

      final uri = ApiConfig.uri(path);
      if (method == 'GET') {
        return _http.get(uri, headers: headers).timeout(timeout);
      }
      return _http
          .post(uri, headers: headers, body: jsonEncode(body ?? const {}))
          .timeout(timeout);
    }

    try {
      var response = await execute();
      if (response.statusCode == 401 && allowRefreshRetry && requireAuth) {
        response = await execute(forceRefresh: true);
      }
      return _decode(response);
    } on TimeoutException {
      throw const ApiException(
        'Sabi is taking longer than expected. Please try again.',
      );
    } on http.ClientException {
      throw const ApiException('Check your internet connection and try again.');
    } finally {
      await trace?.stop();
    }
  }

  Map<String, dynamic> _decode(http.Response response) {
    Map<String, dynamic> json;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        json = decoded;
      } else if (decoded is Map) {
        json = Map<String, dynamic>.from(decoded);
      } else {
        throw ApiException.fromStatus(response.statusCode);
      }
    } catch (_) {
      if (response.statusCode >= 200 && response.statusCode < 300) {
        throw const ApiException(
          'Something went wrong while processing the request.',
        );
      }
      throw ApiException.fromStatus(response.statusCode);
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (json['success'] == false) {
        final error = json['error'];
        final message = error is Map ? (error['message'] as String?) : null;
        throw ApiException(
          message ?? 'Something went wrong while processing the request.',
          statusCode: response.statusCode,
          code: error is Map ? error['code'] as String? : null,
        );
      }
      final data = json['data'];
      if (data is Map<String, dynamic>) return data;
      if (data is Map) return Map<String, dynamic>.from(data);
      return json;
    }

    final error = json['error'];
    final message = error is Map ? (error['message'] as String?) : null;
    final code = error is Map ? (error['code'] as String?) : null;
    throw ApiException.fromStatus(
      response.statusCode,
      code: code,
      bodyMessage: message,
    );
  }
}
