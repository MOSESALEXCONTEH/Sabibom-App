import 'dart:io';
import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../../../core/network/authenticated_api_client.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../app/router.dart';
import '../domain/app_notification.dart';

/// Top-level background handler — required by FCM.
@pragma('vm:entry-point')
Future<void> sabibomFirebaseMessagingBackgroundHandler(
  RemoteMessage message,
) async {
  // Keep lightweight: OS already displays the notification when payload has
  // a `notification` block. Do not duplicate display here.
}

abstract final class SabibomNotificationChannels {
  static const important = AndroidNotificationChannel(
    'sabibom_important',
    'SabiBom Important Alerts',
    description: 'Approvals, cash shortages, and urgent account alerts.',
    importance: Importance.high,
  );

  static const summaries = AndroidNotificationChannel(
    'sabibom_summaries',
    'SabiBom Business Summaries',
    description: 'Daily summaries and weekly reports.',
    importance: Importance.defaultImportance,
  );

  static const general = AndroidNotificationChannel(
    'sabibom_general',
    'SabiBom General Notifications',
    description: 'General business alerts.',
    importance: Importance.defaultImportance,
  );
}

enum PushRegistrationResult {
  registered,
  disabled,
  permissionDenied,
  unavailable,
  failed,
}

/// Registers the device FCM token and Android notification channels.
class PushNotificationBootstrap {
  factory PushNotificationBootstrap() => _instance;

  PushNotificationBootstrap._({
    AuthenticatedApiClient? apiClient,
    ConnectivityService? connectivity,
  }) : _apiClient = apiClient ?? AuthenticatedApiClient(),
       _connectivity = connectivity ?? ConnectivityService();

  static final PushNotificationBootstrap _instance =
      PushNotificationBootstrap._();
  static const _registeredTokenPrefix = 'push.registered_token.';
  final AuthenticatedApiClient _apiClient;
  final ConnectivityService _connectivity;
  static final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();
  static var _initialized = false;
  StreamSubscription<String>? _tokenRefreshSubscription;
  StreamSubscription? _connectivitySubscription;
  StreamSubscription<RemoteMessage>? _foregroundSubscription;
  StreamSubscription<RemoteMessage>? _openedSubscription;
  final Set<String> _registrationsInProgress = <String>{};
  var _initialMessageChecked = false;

  Future<PushRegistrationResult> registerCurrentUserToken() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return PushRegistrationResult.unavailable;
      if (!await _pushEnabledForUser(user.uid)) {
        await unregisterCurrentUserToken();
        return PushRegistrationResult.disabled;
      }

      await _ensureInitialized();

      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (settings.authorizationStatus != AuthorizationStatus.authorized &&
          settings.authorizationStatus != AuthorizationStatus.provisional) {
        return PushRegistrationResult.permissionDenied;
      }

      if (!kIsWeb && Platform.isIOS) {
        await messaging.getAPNSToken();
        await messaging.setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );
      }

      final token = await messaging.getToken();
      if (token == null || token.isEmpty) {
        return PushRegistrationResult.unavailable;
      }
      if (!await _registerTokenIfChanged(user.uid, token)) {
        return PushRegistrationResult.failed;
      }
      _listenForTokenRefresh();
      _listenForConnectivity();
      _listenForNotificationOpens();
      _foregroundSubscription ??= FirebaseMessaging.onMessage.listen(
        _showForegroundIfNeeded,
      );
      return PushRegistrationResult.registered;
    } catch (_) {
      // Notification registration is best-effort and must not affect auth.
      return PushRegistrationResult.failed;
    }
  }

  Future<void> unregisterCurrentUserToken() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null && token.isNotEmpty) {
        await _apiClient
            .postJson(
              '/api/notifications/unregister-device',
              body: <String, dynamic>{'token': token, 'platform': _platform()},
              timeout: const Duration(seconds: 5),
            )
            .catchError((_) => <String, dynamic>{});
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_registeredTokenPrefix${user.uid}');
    } catch (_) {
      // A failed backend cleanup must never prevent logout.
    } finally {
      try {
        await FirebaseMessaging.instance.deleteToken();
      } catch (_) {}
    }
  }

  /// Shows a best-effort device notification after a transaction is saved.
  /// Notification failures must never make a successful transaction look
  /// unsuccessful to the user.
  Future<void> showTransactionConfirmation({
    required int id,
    required String title,
    required String body,
    required String routeName,
    required String routeParameterName,
    required String routeParameterValue,
  }) async {
    try {
      if (kIsWeb) return;
      final user = FirebaseAuth.instance.currentUser;
      if (user == null || !await _pushEnabledForUser(user.uid)) return;
      await _ensureInitialized();
      await _local.show(
        id: id & 0x7fffffff,
        title: title,
        body: body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            SabibomNotificationChannels.general.id,
            SabibomNotificationChannels.general.name,
            channelDescription: SabibomNotificationChannels.general.description,
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
          iOS: const DarwinNotificationDetails(),
        ),
        payload: jsonEncode(<String, String>{
          'routeName': routeName,
          routeParameterName: routeParameterValue,
        }),
      );
    } catch (_) {
      // The transaction is already saved; notification display is optional.
    }
  }

  Future<bool> _registerTokenIfChanged(String uid, String token) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_registeredTokenPrefix$uid';
    final previousToken = prefs.getString(key);
    if (previousToken == token) return true;
    final registrationKey = '$uid:$token';
    if (!_registrationsInProgress.add(registrationKey)) return false;

    try {
      final info = await PackageInfo.fromPlatform();
      await _apiClient.postJson(
        '/api/notifications/register-device',
        body: <String, dynamic>{
          'token': token,
          'platform': _platform(),
          'appVersion': '${info.version}+${info.buildNumber}',
          'notificationsEnabled': true,
        },
      );
      await prefs.setString(key, token);
      if (previousToken != null && previousToken.isNotEmpty) {
        await _unregisterToken(previousToken);
      }
      return true;
    } catch (_) {
      // The connectivity listener and subsequent lifecycle triggers retry.
      return false;
    } finally {
      _registrationsInProgress.remove(registrationKey);
    }
  }

  Future<void> _unregisterToken(String token) async {
    try {
      await _apiClient.postJson(
        '/api/notifications/unregister-device',
        body: <String, dynamic>{'token': token, 'platform': _platform()},
        timeout: const Duration(seconds: 5),
      );
    } catch (_) {
      // Token rotation cleanup is best-effort.
    }
  }

  void _listenForTokenRefresh() {
    _tokenRefreshSubscription ??= FirebaseMessaging.instance.onTokenRefresh
        .listen((token) async {
          try {
            final user = FirebaseAuth.instance.currentUser;
            if (user == null || token.isEmpty) return;
            if (!await _pushEnabledForUser(user.uid)) return;
            final settings = await FirebaseMessaging.instance
                .getNotificationSettings();
            if (settings.authorizationStatus !=
                    AuthorizationStatus.authorized &&
                settings.authorizationStatus !=
                    AuthorizationStatus.provisional) {
              return;
            }
            await _registerTokenIfChanged(user.uid, token);
          } catch (_) {
            // Refresh registration is best-effort and retries later.
          }
        });
  }

  void _listenForConnectivity() {
    _connectivitySubscription ??= _connectivity.onConnectivityChanged.listen((
      _,
    ) async {
      await registerCurrentUserToken();
    });
  }

  Future<bool> _pushEnabledForUser(String uid) async {
    try {
      final user = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      final raw = user.data()?['notificationPrefs'];
      if (raw is Map && raw['pushEnabled'] == false) return false;
    } catch (_) {
      // Registration remains best-effort when preferences cannot be read.
    }
    return true;
  }

  Future<void> _ensureInitialized() async {
    if (_initialized) return;

    if (kIsWeb) {
      _initialized = true;
      return;
    }

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _local.initialize(
      settings: const InitializationSettings(
        android: androidInit,
        iOS: DarwinInitializationSettings(),
      ),
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload == null || payload.isEmpty) return;
        try {
          final decoded = jsonDecode(payload);
          if (decoded is Map) {
            _queueNotificationRoute(
              decoded.map((key, value) => MapEntry('$key', '$value')),
            );
          }
        } catch (_) {
          _queueNotificationRoute(const <String, String>{});
        }
      },
    );

    if (!kIsWeb && Platform.isAndroid) {
      final android = _local
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      await android?.createNotificationChannel(
        SabibomNotificationChannels.important,
      );
      await android?.createNotificationChannel(
        SabibomNotificationChannels.summaries,
      );
      await android?.createNotificationChannel(
        SabibomNotificationChannels.general,
      );
    }
    _initialized = true;
  }

  Future<void> _showForegroundIfNeeded(RemoteMessage message) async {
    if (kIsWeb || (!kIsWeb && Platform.isIOS)) return;
    final notification = message.notification;
    final title = notification?.title ?? message.data['title'] as String?;
    final body = notification?.body ?? message.data['body'] as String?;
    if (title == null || title.isEmpty || body == null || body.isEmpty) return;
    final channel = _channelFor(message.data['channel'] as String?);
    final imageUrl = message.data['imageUrl'] as String?;
    ByteArrayAndroidBitmap? largeImage;
    if (imageUrl != null && imageUrl.startsWith('https://')) {
      try {
        final response = await http
            .get(Uri.parse(imageUrl))
            .timeout(const Duration(seconds: 8));
        if (response.statusCode == 200 &&
            response.bodyBytes.length <= 5 * 1024 * 1024) {
          largeImage = ByteArrayAndroidBitmap(response.bodyBytes);
        }
      } catch (_) {
        // Text notification remains available when rich media cannot load.
      }
    }
    await _local.show(
      id: (message.messageId ?? '${title}_$body').hashCode,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          channel.id,
          channel.name,
          channelDescription: channel.description,
          importance: channel.importance,
          priority: Priority.defaultPriority,
          styleInformation: largeImage == null
              ? null
              : BigPictureStyleInformation(
                  largeImage,
                  contentTitle: title,
                  summaryText: body,
                ),
        ),
      ),
      payload: jsonEncode(message.data),
    );
  }

  void _listenForNotificationOpens() {
    _openedSubscription ??= FirebaseMessaging.onMessageOpenedApp.listen((
      message,
    ) {
      _queueNotificationRoute(message.data);
    });
    if (_initialMessageChecked) return;
    _initialMessageChecked = true;
    FirebaseMessaging.instance.getInitialMessage().then((message) {
      if (message != null) _queueNotificationRoute(message.data);
    });
  }

  void _queueNotificationRoute(Map<String, dynamic> rawData) {
    final data = rawData.map(
      (key, value) => MapEntry(key, value == null ? '' : '$value'),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (FirebaseAuth.instance.currentUser == null) return;
      if (data['tapAction'] == 'none') return;
      final link = Uri.tryParse(data['linkUrl'] ?? '');
      if (link != null && link.scheme == 'https' && link.host.isNotEmpty) {
        launchUrl(link, mode: LaunchMode.externalApplication);
        return;
      }
      final routeName = data['routeName'];
      if (!NotificationRouteAllowlist.isAllowed(routeName)) {
        appRouter.push(AppRoutes.notifications);
        return;
      }

      final pathParameters = <String, String>{
        for (final key in const {
          'productId',
          'customerId',
          'supplierId',
          'expenseId',
          'saleId',
          'purchaseId',
          'approvalId',
          'dateKey',
          'weekKey',
        })
          if (data[key]?.isNotEmpty == true) key: data[key]!,
      };
      final queryParameters = <String, String>{
        for (final entry in data.entries)
          if (entry.key != 'routeName' &&
              !pathParameters.containsKey(entry.key) &&
              entry.value.isNotEmpty)
            entry.key: entry.value,
      };
      try {
        const shellRoutes = {
          AppRouteNames.products,
          AppRouteNames.productDetails,
          AppRouteNames.customers,
          AppRouteNames.customerDetails,
          AppRouteNames.suppliers,
          AppRouteNames.supplierDetails,
        };
        if (shellRoutes.contains(routeName)) {
          appRouter.goNamed(
            routeName!,
            pathParameters: pathParameters,
            queryParameters: queryParameters,
          );
        } else {
          appRouter.pushNamed(
            routeName!,
            pathParameters: pathParameters,
            queryParameters: queryParameters,
          );
        }
      } catch (_) {
        appRouter.push(AppRoutes.notifications);
      }
    });
  }

  AndroidNotificationChannel _channelFor(String? id) {
    return switch (id) {
      'sabibom_important' => SabibomNotificationChannels.important,
      'sabibom_summaries' => SabibomNotificationChannels.summaries,
      _ => SabibomNotificationChannels.general,
    };
  }

  String _platform() {
    if (kIsWeb) return 'web';
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    return 'other';
  }
}

final pushNotificationBootstrapProvider = Provider<PushNotificationBootstrap>((
  ref,
) {
  return PushNotificationBootstrap();
});
