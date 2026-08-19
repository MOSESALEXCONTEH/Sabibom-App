// ignore_for_file: avoid_types_as_parameter_names

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/app_notification.dart';
import '../domain/notification_preferences.dart';

export '../domain/app_notification.dart';
export '../domain/notification_preferences.dart';

class NotificationsRepository {
  NotificationsRepository({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> _col(String userId) =>
      _db.collection('users').doc(userId).collection('notifications');

  DocumentReference<Map<String, dynamic>> _prefsDoc({
    required String userId,
    String? businessId,
  }) {
    final key = (businessId == null || businessId.isEmpty)
        ? '_account'
        : businessId;
    return _db
        .collection('users')
        .doc(userId)
        .collection('notification_preferences')
        .doc(key);
  }

  DocumentReference<Map<String, dynamic>> _eventDoc(String key) =>
      _db.collection('notification_events').doc(key);

  Future<String?> createNotification({
    required String userId,
    required AppNotificationType type,
    required String title,
    required String body,
    String? businessId,
    String? businessName,
    String? branchId,
    String? entityType,
    String? entityId,
    String? routeName,
    Map<String, String>? routeParameters,
    String? actionLabel,
    String? deduplicationKey,
    String? sourceType,
    String? sourceId,
    NotificationPriority? priority,
    Map<String, Object?>? data,
    String generatedBy = 'client',
  }) async {
    if (userId.isEmpty) return null;

    // Deduplicate by stable key when provided.
    if (deduplicationKey != null && deduplicationKey.isNotEmpty) {
      final eventRef = _eventDoc(deduplicationKey);
      final eventSnap = await eventRef.get();
      if (eventSnap.exists) {
        final state = eventSnap.data()?['state'] as String?;
        if (state == 'active' || state == 'delivered') {
          return eventSnap.data()?['notificationId'] as String?;
        }
      }
    }

    final ref = _col(userId).doc();
    final notification = AppNotification(
      id: ref.id,
      userId: userId,
      businessId: businessId,
      businessName: businessName,
      branchId: branchId,
      type: type,
      category: type.category,
      title: title,
      message: body,
      priority: priority ?? type.defaultPriority,
      status: NotificationStatus.unread,
      entityType: entityType,
      entityId: entityId,
      routeName: routeName,
      routeParameters: routeParameters ?? const {},
      actionLabel: actionLabel,
      deduplicationKey: deduplicationKey,
      sourceType: sourceType,
      sourceId: sourceId,
      generatedBy: generatedBy,
      metadata: data ?? const {},
    );

    await ref.set(notification.toCreateMap(userId: userId));

    if (deduplicationKey != null && deduplicationKey.isNotEmpty) {
      await _eventDoc(deduplicationKey).set({
        'key': deduplicationKey,
        'type': type.storedValue,
        'businessId': businessId,
        'branchId': branchId,
        'userId': userId,
        'sourceId': sourceId ?? entityId,
        'state': 'delivered',
        'notificationId': ref.id,
        'firstGeneratedAt': FieldValue.serverTimestamp(),
        'lastGeneratedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    return ref.id;
  }

  Future<void> resolveEvent(String deduplicationKey) async {
    if (deduplicationKey.isEmpty) return;
    await _eventDoc(deduplicationKey).set({
      'state': 'resolved',
      'resolvedAt': FieldValue.serverTimestamp(),
      'lastGeneratedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Stream<List<AppNotification>> watchNotifications(
    String userId, {
    int limit = 80,
    NotificationStatus? status,
    NotificationCategory? category,
    String? businessId,
  }) {
    if (userId.isEmpty) return Stream.value(const []);
    Query<Map<String, dynamic>> q = _col(
      userId,
    ).orderBy('createdAt', descending: true);
    if (status != null) {
      q = _col(userId)
          .where('status', isEqualTo: status.storedValue)
          .orderBy('createdAt', descending: true);
    }
    return q.limit(limit).snapshots().map((snap) {
      var items = snap.docs
          .map((d) => AppNotification.fromMap(d.id, d.data()))
          .toList();
      // Client-side filters for compatibility with legacy docs missing status.
      if (status == NotificationStatus.unread) {
        items = items.where((n) => n.isUnread).toList();
      } else if (status == NotificationStatus.read) {
        items = items
            .where((n) => n.status == NotificationStatus.read)
            .toList();
      } else if (status == NotificationStatus.archived) {
        items = items.where((n) => n.isArchived).toList();
      }
      if (category != null) {
        items = items.where((n) => n.category == category).toList();
      }
      if (businessId != null && businessId.isNotEmpty) {
        items = items
            .where((n) => n.businessId == null || n.businessId == businessId)
            .toList();
      }
      return items;
    });
  }

  Stream<int> watchUnreadCount(String userId) {
    if (userId.isEmpty) return Stream.value(0);
    return _col(userId)
        .where('status', isEqualTo: NotificationStatus.unread.storedValue)
        .limit(100)
        .snapshots()
        .map((snap) {
          // Also count legacy unread (read == false, no status).
          return snap.size;
        })
        .asyncMap((unreadCount) async {
          if (unreadCount > 0) return unreadCount;
          final legacy = await _col(
            userId,
          ).where('read', isEqualTo: false).limit(100).get();
          return legacy.docs
              .where((d) => (d.data()['status'] as String?) != 'archived')
              .length;
        });
  }

  Future<void> markRead(String userId, String notificationId) async {
    await _col(userId).doc(notificationId).update({
      'status': NotificationStatus.read.storedValue,
      'read': true,
      'readAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> markUnread(String userId, String notificationId) async {
    await _col(userId).doc(notificationId).update({
      'status': NotificationStatus.unread.storedValue,
      'read': false,
      'readAt': null,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> archive(String userId, String notificationId) async {
    await _col(userId).doc(notificationId).update({
      'status': NotificationStatus.archived.storedValue,
      'read': true,
      'archivedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> restore(String userId, String notificationId) async {
    await _col(userId).doc(notificationId).update({
      'status': NotificationStatus.read.storedValue,
      'archivedAt': null,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> markAllRead(String userId) async {
    final unread = await _col(userId)
        .where('status', isEqualTo: NotificationStatus.unread.storedValue)
        .limit(50)
        .get();
    final legacy = await _col(
      userId,
    ).where('read', isEqualTo: false).limit(50).get();
    final ids = <String>{
      ...unread.docs.map((d) => d.id),
      ...legacy.docs.map((d) => d.id),
    };
    if (ids.isEmpty) return;
    final batch = _db.batch();
    for (final id in ids.take(50)) {
      batch.update(_col(userId).doc(id), {
        'status': NotificationStatus.read.storedValue,
        'read': true,
        'readAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  Future<void> markManyRead(
    String userId,
    Iterable<String> notificationIds,
  ) async {
    final ids = notificationIds.toSet().take(50).toList(growable: false);
    if (ids.isEmpty) return;
    final batch = _db.batch();
    for (final id in ids) {
      batch.update(_col(userId).doc(id), {
        'status': NotificationStatus.read.storedValue,
        'read': true,
        'readAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  /// Permanently deletes archived notifications (up to 100 per call).
  Future<int> deleteArchived(String userId) async {
    final archived = await _col(userId)
        .where('status', isEqualTo: NotificationStatus.archived.storedValue)
        .limit(100)
        .get();
    if (archived.docs.isEmpty) return 0;
    final batch = _db.batch();
    for (final doc in archived.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
    return archived.docs.length;
  }

  Future<int> deleteMany(
    String userId,
    Iterable<String> notificationIds,
  ) async {
    final ids = notificationIds.toSet().take(100).toList(growable: false);
    if (ids.isEmpty) return 0;
    final batch = _db.batch();
    for (final id in ids) {
      batch.delete(_col(userId).doc(id));
    }
    await batch.commit();
    return ids.length;
  }

  Future<NotificationPreferences> getPreferences({
    required String userId,
    String? businessId,
  }) async {
    final snap = await _prefsDoc(userId: userId, businessId: businessId).get();
    if (snap.exists) {
      return NotificationPreferences.fromMap(snap.data());
    }
    // Fallback to legacy user.notificationPrefs
    final user = await _db.collection('users').doc(userId).get();
    final legacy = user.data()?['notificationPrefs'];
    if (legacy is Map) {
      return NotificationPreferences.fromMap(Map<String, dynamic>.from(legacy));
    }
    return const NotificationPreferences();
  }

  Stream<NotificationPreferences> watchPreferences({
    required String userId,
    String? businessId,
  }) {
    return _prefsDoc(
      userId: userId,
      businessId: businessId,
    ).snapshots().asyncMap((snap) async {
      if (snap.exists) {
        return NotificationPreferences.fromMap(snap.data());
      }
      return getPreferences(userId: userId, businessId: businessId);
    });
  }

  Future<void> savePreferences({
    required String userId,
    String? businessId,
    required NotificationPreferences prefs,
  }) async {
    final payload = <String, Object?>{
      'userId': userId,
      'inAppEnabled': prefs.inAppEnabled,
      'pushEnabled': prefs.pushEnabled,
      'lowStockEnabled': prefs.lowStockEnabled,
      'outOfStockEnabled': prefs.outOfStockEnabled,
      'customerDebtEnabled': prefs.customerDebtEnabled,
      'supplierPaymentEnabled': prefs.supplierPaymentEnabled,
      'approvalEnabled': prefs.approvalEnabled,
      'endOfDayEnabled': prefs.endOfDayEnabled,
      'largeExpenseEnabled': prefs.largeExpenseEnabled,
      'staffActivityEnabled': prefs.staffActivityEnabled,
      'dailySummaryEnabled': prefs.dailySummaryEnabled,
      'weeklyReportEnabled': prefs.weeklyReportEnabled,
      'dailySummaryTime': prefs.dailySummaryTime,
      'weeklyReportDay': prefs.weeklyReportDay,
      'weeklyReportTime': prefs.weeklyReportTime,
      'endOfDayReminderTime': prefs.endOfDayReminderTime,
      'quietHoursEnabled': prefs.quietHoursEnabled,
      'quietHoursStart': prefs.quietHoursStart,
      'quietHoursEnd': prefs.quietHoursEnd,
      'customerDebtMinimumMinor': prefs.customerDebtMinimumMinor,
      'supplierDebtMinimumMinor': prefs.supplierDebtMinimumMinor,
      'largeExpenseThresholdMinor': prefs.largeExpenseThresholdMinor,
      'timezone': prefs.timezone,
      'updatedAt': FieldValue.serverTimestamp(),
      // Legacy mirror keys for older readers.
      'sales': prefs.dailySummaryEnabled || prefs.endOfDayEnabled,
      'lowStock': prefs.lowStockEnabled,
      'customerCredit': prefs.customerDebtEnabled,
      'team': prefs.staffActivityEnabled,
    };
    if (businessId != null && businessId.isNotEmpty) {
      payload['businessId'] = businessId;
    }

    Object? prefsError;
    Object? userError;

    try {
      await _prefsDoc(
        userId: userId,
        businessId: businessId,
      ).set(payload, SetOptions(merge: true));
    } catch (error) {
      prefsError = error;
    }

    try {
      final legacy = Map<String, Object?>.from(payload)
        ..['updatedAt'] = Timestamp.now()
        ..removeWhere((_, value) => value == null || value is FieldValue);
      await _db.collection('users').doc(userId).set({
        'notificationPrefs': legacy,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (error) {
      userError = error;
    }

    if (prefsError != null && userError != null) {
      throw prefsError;
    }
  }

  Future<void> saveDeviceToken({
    required String userId,
    required String deviceId,
    required String fcmToken,
    required String platform,
    String? appVersion,
    String? deviceName,
  }) async {
    await _db
        .collection('users')
        .doc(userId)
        .collection('devices')
        .doc(deviceId)
        .set({
          'deviceId': deviceId,
          'userId': userId,
          'fcmToken': fcmToken,
          'platform': platform,
          'appVersion': appVersion,
          'deviceName': deviceName,
          'isActive': true,
          'notificationsEnabled': true,
          'updatedAt': FieldValue.serverTimestamp(),
          'lastSeenAt': FieldValue.serverTimestamp(),
          'createdAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

    // Legacy array for older push code paths.
    await _db.collection('users').doc(userId).set({
      'fcmTokens': FieldValue.arrayUnion([fcmToken]),
      'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> deactivateDevice({
    required String userId,
    required String deviceId,
  }) async {
    await _db
        .collection('users')
        .doc(userId)
        .collection('devices')
        .doc(deviceId)
        .set({
          'isActive': false,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
  }

  /// Backward-compatible alias used by older call sites.
  Future<void> saveFcmToken(String userId, String token) async {
    await saveDeviceToken(
      userId: userId,
      deviceId: 'legacy_default',
      fcmToken: token,
      platform: 'android',
    );
  }
}

final notificationsRepositoryProvider = Provider<NotificationsRepository>((
  ref,
) {
  return NotificationsRepository();
});

final currentUserNotificationsProvider = StreamProvider<List<AppNotification>>((
  ref,
) {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return Stream.value(const []);
  return ref.watch(notificationsRepositoryProvider).watchNotifications(uid);
});

final unreadNotificationCountProvider = StreamProvider<int>((ref) {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return Stream.value(0);
  return ref.watch(notificationsRepositoryProvider).watchUnreadCount(uid);
});

/// Backward-compatible alias.
final unreadNotificationsCountProvider = Provider<int>((ref) {
  return ref.watch(unreadNotificationCountProvider).asData?.value ?? 0;
});

final notificationPreferencesProvider =
    StreamProvider.family<NotificationPreferences, String?>((ref, businessId) {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        return Stream.value(const NotificationPreferences());
      }
      return ref
          .watch(notificationsRepositoryProvider)
          .watchPreferences(userId: uid, businessId: businessId);
    });
