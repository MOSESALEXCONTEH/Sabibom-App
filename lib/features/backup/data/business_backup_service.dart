import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

import '../../business_setup/domain/business.dart';
import '../../team/domain/system_roles.dart';

class BackupManifest {
  const BackupManifest({
    required this.version,
    required this.businessId,
    required this.businessName,
    required this.exportedAt,
    required this.counts,
    required this.isDemoSource,
  });

  final int version;
  final String businessId;
  final String businessName;
  final DateTime exportedAt;
  final Map<String, int> counts;
  final bool isDemoSource;

  Map<String, Object?> toMap() => {
        'version': version,
        'businessId': businessId,
        'businessName': businessName,
        'exportedAt': exportedAt.toIso8601String(),
        'counts': counts,
        'isDemoSource': isDemoSource,
        'includesSecrets': false,
      };
}

class BusinessBackupService {
  BusinessBackupService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _db = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  static const _collections = <String>[
    'products',
    'customers',
    'suppliers',
    'expenses',
    'expense_categories',
    'sales',
    'purchases',
    'inventory_batches',
    'inventory_movements',
    'roles',
  ];

  Future<File> exportBackup(String businessId) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Sign in to create a backup.');
    if (businessId.isEmpty) throw StateError('Select a business first.');

    final bizSnap = await _db.collection('businesses').doc(businessId).get();
    if (!bizSnap.exists) throw StateError('Business not found.');
    final bizData = bizSnap.data()!;
    if (bizData['ownerId'] != user.uid && bizData['isDemo'] != true) {
      // Allow owners; members with export permission checked in UI.
    }

    final payload = <String, Object?>{
      'manifest': null,
      'business': _serializeValue(_stripSecrets(bizData)),
      'collections': <String, Object?>{},
    };
    final counts = <String, int>{};

    for (final name in _collections) {
      final snap = await _db
          .collection('businesses')
          .doc(businessId)
          .collection(name)
          .limit(2000)
          .get();
      final docs = <Map<String, Object?>>[];
      for (final doc in snap.docs) {
        docs.add({
          'id': doc.id,
          'data': _serializeValue(_stripSecrets(doc.data()))
              as Map<String, Object?>,
        });
      }
      (payload['collections'] as Map<String, Object?>)[name] = docs;
      counts[name] = docs.length;
    }

    final manifest = BackupManifest(
      version: 1,
      businessId: businessId,
      businessName: (bizData['name'] as String?) ?? 'Business',
      exportedAt: DateTime.now().toUtc(),
      counts: counts,
      isDemoSource: bizData['isDemo'] == true,
    );
    payload['manifest'] = manifest.toMap();

    final dir = await getApplicationDocumentsDirectory();
    var safeName =
        manifest.businessName.replaceAll(RegExp(r'[^a-zA-Z0-9_-]+'), '_');
    if (safeName.isEmpty) safeName = 'Business';
    if (safeName.length > 40) safeName = safeName.substring(0, 40);
    final stamp = DateFormatStamp.now();
    final file = File(
      '${dir.path}/SabiBom_Backup_${safeName}_$stamp.json',
    );
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(payload),
      flush: true,
    );

    try {
      await _db.collection('users').doc(user.uid).set({
        'lastBackupAt': FieldValue.serverTimestamp(),
        'lastBackupBusinessId': businessId,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await _db.collection('businesses').doc(businessId).set({
        'lastBackupAt': FieldValue.serverTimestamp(),
        'lastBackupBy': user.uid,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {
      // Local file is the source of truth; metadata updates are best-effort.
    }

    return file;
  }

  Future<void> shareBackup(File file) async {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        text: 'SabiBom business backup',
        subject: 'SabiBom backup',
      ),
    );
  }

  /// Restores backup as a **new** business owned by the current user.
  Future<String> restoreAsNewBusiness(File backupFile) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Sign in to restore a backup.');

    final raw = jsonDecode(await backupFile.readAsString());
    if (raw is! Map) throw StateError('Invalid backup file.');
    final map = Map<String, dynamic>.from(raw);
    final businessRaw = map['business'];
    final collections = map['collections'];
    if (businessRaw is! Map || collections is! Map) {
      throw StateError('Backup is missing business data.');
    }

    final source = Map<String, dynamic>.from(businessRaw);
    final newId =
        'restored_${const Uuid().v4().replaceAll('-', '').substring(0, 16)}';
    final name =
        '${(source['name'] as String?)?.trim().isNotEmpty == true ? source['name'] : 'Restored Business'} (Restored)';

    final business = Business.fromFirestore({
      ...source,
      'businessId': newId,
      'name': name,
      'ownerId': user.uid,
      'isDemo': false,
      'status': 'active',
    });

    final bizRef = _db.collection('businesses').doc(newId);
    await bizRef.set({
      ...business.toMap(),
      'restoredFromBusinessId': source['businessId'],
      'restoredAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await bizRef.collection('members').doc(user.uid).set({
      'userId': user.uid,
      'role': SystemRoleIds.owner,
      'roleId': SystemRoleIds.owner,
      'status': 'active',
      'isOwner': true,
      'permissions': SystemRoles.defaultPermissionsFor(SystemRoleIds.owner)
          .map((p) => p.code)
          .toList(),
      'createdAt': FieldValue.serverTimestamp(),
    });

    for (final entry in collections.entries) {
      final colName = '${entry.key}';
      final docs = entry.value;
      if (docs is! List) continue;
      var batch = _db.batch();
      var ops = 0;
      for (final item in docs.take(1500)) {
        if (item is! Map) continue;
        final id = '${item['id'] ?? ''}';
        final data = item['data'];
        if (id.isEmpty || data is! Map) continue;
        final cleaned = _deserializeDoc(
          _stripSecrets(Map<String, dynamic>.from(data)),
        );
        cleaned['businessId'] = newId;
        cleaned.remove('fcmToken');
        cleaned.remove('fcmTokens');
        batch.set(bizRef.collection(colName).doc(id), cleaned);
        ops++;
        if (ops >= 400) {
          await batch.commit();
          batch = _db.batch();
          ops = 0;
        }
      }
      if (ops > 0) await batch.commit();
    }

    await _db.collection('users').doc(user.uid).set({
      'activeBusinessId': newId,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    return newId;
  }

  Map<String, dynamic> _stripSecrets(Map<String, dynamic> data) {
    final out = Map<String, dynamic>.from(data);
    const banned = {
      'fcmToken',
      'fcmTokens',
      'apiKey',
      'privateKey',
      'password',
      'idToken',
      'refreshToken',
      'pinataJwt',
      'secret',
    };
    out.removeWhere((k, _) => banned.contains(k));
    return out;
  }

  Object? _serializeValue(Object? value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate().toUtc().toIso8601String();
    if (value is DateTime) return value.toUtc().toIso8601String();
    if (value is GeoPoint) {
      return <String, Object?>{
        '_type': 'geopoint',
        'latitude': value.latitude,
        'longitude': value.longitude,
      };
    }
    if (value is DocumentReference) {
      return <String, Object?>{'_type': 'ref', 'path': value.path};
    }
    if (value is Map) {
      final out = <String, Object?>{};
      value.forEach((k, v) {
        out['$k'] = _serializeValue(v);
      });
      return out;
    }
    if (value is Iterable && value is! String) {
      return value.map(_serializeValue).toList(growable: false);
    }
    if (value is num || value is bool || value is String) return value;
    return value.toString();
  }

  Map<String, dynamic> _deserializeDoc(Map<String, dynamic> data) {
    final out = <String, dynamic>{};
    data.forEach((key, value) {
      out[key] = _deserializeValue(value);
    });
    return out;
  }

  Object? _deserializeValue(Object? value) {
    if (value == null) return null;
    if (value is String) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null &&
          (value.contains('T') || value.contains('-')) &&
          value.length >= 10) {
        // Heuristic: ISO-8601 timestamps from export become Firestore timestamps.
        if (RegExp(r'^\d{4}-\d{2}-\d{2}T').hasMatch(value) ||
            RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
          return Timestamp.fromDate(parsed.toUtc());
        }
      }
      return value;
    }
    if (value is Map) {
      final map = Map<String, dynamic>.from(value);
      if (map['_type'] == 'geopoint') {
        return GeoPoint(
          (map['latitude'] as num?)?.toDouble() ?? 0,
          (map['longitude'] as num?)?.toDouble() ?? 0,
        );
      }
      final out = <String, dynamic>{};
      map.forEach((k, v) {
        if (k == '_type') return;
        out[k] = _deserializeValue(v);
      });
      return out;
    }
    if (value is Iterable && value is! String) {
      return value.map(_deserializeValue).toList(growable: false);
    }
    return value;
  }
}

abstract final class DateFormatStamp {
  static String now() {
    final d = DateTime.now();
    String p(int n) => n.toString().padLeft(2, '0');
    return '${d.year}${p(d.month)}${p(d.day)}_${p(d.hour)}${p(d.minute)}';
  }
}
