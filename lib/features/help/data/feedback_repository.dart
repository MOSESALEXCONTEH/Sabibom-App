import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:package_info_plus/package_info_plus.dart';

enum FeedbackCategory {
  bug,
  featureRequest('feature_request'),
  calculationIssue('calculation_issue'),
  sabiIssue('sabi_issue'),
  receiptIssue('receipt_issue'),
  accountIssue('account_issue'),
  other;

  const FeedbackCategory([this._stored]);
  final String? _stored;
  String get storedValue => _stored ?? name;

  String get label => switch (this) {
        FeedbackCategory.bug => 'Bug',
        FeedbackCategory.featureRequest => 'Feature request',
        FeedbackCategory.calculationIssue => 'Calculation issue',
        FeedbackCategory.sabiIssue => 'Sabi issue',
        FeedbackCategory.receiptIssue => 'Receipt issue',
        FeedbackCategory.accountIssue => 'Account issue',
        FeedbackCategory.other => 'Other',
      };
}

class SafeDiagnostics {
  const SafeDiagnostics({
    required this.appVersion,
    required this.buildNumber,
    required this.platform,
    this.androidVersion,
    this.deviceModel,
    this.currentRoute,
  });

  final String appVersion;
  final String buildNumber;
  final String platform;
  final String? androidVersion;
  final String? deviceModel;
  final String? currentRoute;

  Map<String, Object?> toMap() => {
        'appVersion': appVersion,
        'buildNumber': buildNumber,
        'platform': platform,
        'androidVersion': androidVersion,
        'deviceModel': deviceModel,
        'currentRoute': currentRoute,
      };

  static Future<SafeDiagnostics> collect({String? currentRoute}) async {
    final info = await PackageInfo.fromPlatform();
    return SafeDiagnostics(
      appVersion: info.version,
      buildNumber: info.buildNumber,
      platform: 'android',
      currentRoute: currentRoute,
    );
  }
}

class FeedbackRepository {
  FeedbackRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  Future<String> submit({
    required String userId,
    required FeedbackCategory category,
    required String title,
    required String description,
    String? businessId,
    SafeDiagnostics? diagnostics,
    String? attachmentUrl,
    String? attachmentCid,
  }) async {
    final id = _db.collection('feedback').doc().id;
    final payload = <String, Object?>{
      'id': id,
      'userId': userId,
      'category': category.storedValue,
      'title': title.trim(),
      'description': description.trim(),
      'priority': 'normal',
      'status': 'new',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    void put(String key, Object? value) {
      if (value != null) payload[key] = value;
    }

    put('businessId', businessId);
    put('appVersion', diagnostics?.appVersion);
    put('buildNumber', diagnostics?.buildNumber);
    put('platform', diagnostics?.platform);
    put('androidVersion', diagnostics?.androidVersion);
    put('deviceModel', diagnostics?.deviceModel);
    put('currentRoute', diagnostics?.currentRoute);
    if (diagnostics != null) {
      final diag = <String, Object?>{};
      diagnostics.toMap().forEach((k, v) {
        if (v != null) diag[k] = v;
      });
      if (diag.isNotEmpty) payload['safeDiagnostics'] = diag;
    }
    put('attachmentUrl', attachmentUrl);
    put('attachmentCid', attachmentCid);

    // 1) User-scoped collection (works after rules deploy).
    // 2) Top-level inbox (support triage).
    // 3) Fallback onto the user profile doc (always allowed by users/{uid} update).
    var saved = false;
    Object? lastError;

    try {
      await _db
          .collection('users')
          .doc(userId)
          .collection('feedback')
          .doc(id)
          .set(payload);
      saved = true;
    } catch (error) {
      lastError = error;
    }

    try {
      await _db.collection('feedback').doc(id).set(payload);
      saved = true;
    } catch (error) {
      lastError = error;
    }

    if (!saved) {
      final plain = Map<String, Object?>.from(payload)
        ..['createdAt'] = Timestamp.now()
        ..['updatedAt'] = Timestamp.now()
        ..removeWhere((_, value) => value == null || value is FieldValue);
      await _db.collection('users').doc(userId).set({
        'lastFeedback': plain,
        'lastFeedbackId': id,
        'lastFeedbackAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      saved = true;
    }

    if (!saved && lastError != null) {
      throw lastError;
    }
    return id;
  }
}
