import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/business_profile/services/pinata_upload_service.dart';
import '../network/api_exception.dart';
import '../network/authenticated_api_client.dart';
import '../services/image_compression_service.dart';

enum OfflineMutationType {
  productCreate,
  saleComplete,
  purchaseComplete,
  mediaUpload,
}

class OfflineMutation {
  const OfflineMutation({
    required this.id,
    required this.type,
    required this.userId,
    required this.businessId,
    required this.payload,
    required this.createdAt,
    this.lastError,
    this.attemptCount = 0,
    this.nextAttemptAt,
  });

  factory OfflineMutation.fromJson(Map<String, dynamic> json) =>
      OfflineMutation(
        id: json['id'] as String,
        type: OfflineMutationType.values.byName(json['type'] as String),
        userId: json['userId'] as String,
        businessId: json['businessId'] as String,
        payload: Map<String, dynamic>.from(json['payload'] as Map),
        createdAt: DateTime.parse(json['createdAt'] as String).toUtc(),
        lastError: json['lastError'] as String?,
        attemptCount: (json['attemptCount'] as num?)?.toInt() ?? 0,
        nextAttemptAt: json['nextAttemptAt'] == null
            ? null
            : DateTime.parse(json['nextAttemptAt'] as String).toUtc(),
      );

  final String id;
  final OfflineMutationType type;
  final String userId;
  final String businessId;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final String? lastError;
  final int attemptCount;
  final DateTime? nextAttemptAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'type': type.name,
    'userId': userId,
    'businessId': businessId,
    'payload': payload,
    'createdAt': createdAt.toIso8601String(),
    if (lastError != null) 'lastError': lastError,
    if (attemptCount > 0) 'attemptCount': attemptCount,
    if (nextAttemptAt != null)
      'nextAttemptAt': nextAttemptAt!.toIso8601String(),
  };

  OfflineMutation copyWith({
    String? lastError,
    int? attemptCount,
    DateTime? nextAttemptAt,
  }) => OfflineMutation(
    id: id,
    type: type,
    userId: userId,
    businessId: businessId,
    payload: payload,
    createdAt: createdAt,
    lastError: lastError ?? this.lastError,
    attemptCount: attemptCount ?? this.attemptCount,
    nextAttemptAt: nextAttemptAt ?? this.nextAttemptAt,
  );
}

/// A retained queue record that could not safely be replayed.
class OfflineMutationQuarantineEntry {
  const OfflineMutationQuarantineEntry({
    required this.reason,
    required this.quarantinedAt,
    this.mutation,
    this.raw,
    this.error,
  });

  factory OfflineMutationQuarantineEntry.fromJson(Map<String, dynamic> json) =>
      OfflineMutationQuarantineEntry(
        reason: json['reason'] as String,
        quarantinedAt: DateTime.parse(json['quarantinedAt'] as String).toUtc(),
        mutation: json['mutation'] == null
            ? null
            : OfflineMutation.fromJson(
                Map<String, dynamic>.from(json['mutation'] as Map),
              ),
        raw: json['raw'],
        error: json['error'] as String?,
      );

  final String reason;
  final DateTime quarantinedAt;
  final OfflineMutation? mutation;
  final Object? raw;
  final String? error;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'reason': reason,
    'quarantinedAt': quarantinedAt.toIso8601String(),
    if (mutation != null) 'mutation': mutation!.toJson(),
    if (raw != null) 'raw': raw,
    if (error != null) 'error': error,
  };
}

class OfflineMutationQueue {
  OfflineMutationQueue({
    FirebaseAuth? auth,
    String? Function()? currentUserId,
    FirebaseFirestore? firestore,
    AuthenticatedApiClient? apiClient,
    PinataUploadService? pinata,
    Future<void> Function(OfflineMutation mutation)? executeOverride,
    DateTime Function()? now,
  }) : _currentUserId =
           currentUserId ??
           (() {
             try {
               return (auth ?? FirebaseAuth.instance).currentUser?.uid;
             } catch (_) {
               return null;
             }
           }),
       _firestoreOverride = firestore,
       _apiOverride = apiClient,
       _pinataOverride = pinata,
       // ignore: prefer_initializing_formals
       _executeOverride = executeOverride,
       _now = now ?? (() => DateTime.now().toUtc());

  /// Stable key used by the legacy bare-list queue and current envelope.
  static const storageKey = 'sabibom_offline_mutations_v1';
  static const envelopeVersion = 2;
  static const _initialBackoff = Duration(seconds: 30);
  static const _maximumBackoff = Duration(hours: 6);

  /// Serializes preference read-modify-write work across queue instances.
  static Future<void> _storageBarrier = Future<void>.value();

  final String? Function() _currentUserId;
  final FirebaseFirestore? _firestoreOverride;
  final AuthenticatedApiClient? _apiOverride;
  final PinataUploadService? _pinataOverride;
  final Future<void> Function(OfflineMutation mutation)? _executeOverride;
  final DateTime Function() _now;
  final _changes = StreamController<void>.broadcast();
  Future<void>? _syncOperation;

  FirebaseFirestore get _firestore =>
      _firestoreOverride ?? FirebaseFirestore.instance;
  AuthenticatedApiClient get _api => _apiOverride ?? AuthenticatedApiClient();
  PinataUploadService get _pinata =>
      _pinataOverride ?? FirebasePinataUploadService();
  Stream<void> get changes => _changes.stream;

  void dispose() => _changes.close();

  Future<List<OfflineMutation>> pending({String? businessId}) async {
    final uid = _currentUserId();
    if (uid == null) return const <OfflineMutation>[];
    final envelope = await _readEnvelope();
    return envelope.mutations
        .where(
          (item) =>
              item.userId == uid &&
              (businessId == null || item.businessId == businessId),
        )
        .toList(growable: false);
  }

  Future<List<OfflineMutationQuarantineEntry>> quarantined() async =>
      List<OfflineMutationQuarantineEntry>.unmodifiable(
        (await _readEnvelope()).quarantined,
      );

  Future<void> enqueue({
    required String id,
    required OfflineMutationType type,
    required String businessId,
    required Map<String, dynamic> payload,
  }) async {
    final uid = _currentUserId();
    if (uid == null) throw StateError('A signed-in user is required.');
    await _updateEnvelope((envelope) {
      final item = OfflineMutation(
        id: id,
        type: type,
        userId: uid,
        businessId: businessId,
        payload: payload,
        createdAt: _now().toUtc(),
      );
      final index = envelope.mutations.indexWhere(
        (candidate) => candidate.id == id && candidate.userId == uid,
      );
      if (index < 0) {
        envelope.mutations.add(item);
      } else {
        envelope.mutations[index] = item;
      }
    });
  }

  /// Concurrent replay triggers share one serialized pass.
  Future<void> syncPending() {
    final active = _syncOperation;
    if (active != null) return active;
    late final Future<void> operation;
    operation = _runSyncPending().whenComplete(() {
      if (identical(_syncOperation, operation)) _syncOperation = null;
    });
    _syncOperation = operation;
    return operation;
  }

  Future<void> _runSyncPending() async {
    final uid = _currentUserId();
    if (uid == null) return;
    final snapshot = (await _readEnvelope()).mutations;
    for (final item in List<OfflineMutation>.from(snapshot)) {
      if (item.userId != uid) continue;
      final now = _now().toUtc();
      if (item.nextAttemptAt?.isAfter(now) ?? false) {
        if (item.type == OfflineMutationType.productCreate) break;
        continue;
      }
      try {
        await (_executeOverride?.call(item) ?? _execute(item));
        await _updateEnvelope((envelope) {
          envelope.mutations.removeWhere(
            (candidate) => _isSameRevision(candidate, item),
          );
        });
      } catch (error) {
        await _updateEnvelope((envelope) {
          final index = envelope.mutations.indexWhere(
            (candidate) => _isSameRevision(candidate, item),
          );
          if (index < 0) return;
          if (_isTerminalError(error)) {
            envelope.mutations.removeAt(index);
            envelope.quarantined.add(
              OfflineMutationQuarantineEntry(
                reason: 'terminal_error',
                quarantinedAt: now,
                mutation: item,
                error: '$error',
              ),
            );
            return;
          }
          final attempts = item.attemptCount + 1;
          envelope.mutations[index] = item.copyWith(
            lastError: '$error',
            attemptCount: attempts,
            nextAttemptAt: now.add(_backoffFor(attempts)),
          );
        });
        // Product media depends on its preceding product creation.
        if (item.type == OfflineMutationType.productCreate) break;
      }
    }
  }

  bool _isSameRevision(OfflineMutation candidate, OfflineMutation item) =>
      candidate.id == item.id &&
      candidate.userId == item.userId &&
      candidate.createdAt == item.createdAt;

  Duration _backoffFor(int attemptCount) {
    final exponent = (attemptCount - 1).clamp(0, 20);
    final seconds = _initialBackoff.inSeconds * (1 << exponent);
    return Duration(seconds: seconds.clamp(0, _maximumBackoff.inSeconds));
  }

  bool _isTerminalError(Object error) {
    if (error is ApiException) {
      final status = error.statusCode;
      return status != null &&
          status >= 400 &&
          status < 500 &&
          status != 401 &&
          status != 408 &&
          status != 409 &&
          status != 429;
    }
    if (error is FirebaseException) {
      return const <String>{
        'invalid-argument',
        'not-found',
        'permission-denied',
        'failed-precondition',
      }.contains(error.code);
    }
    return error is StateError ||
        error is FormatException ||
        error is TypeError;
  }

  Future<void> _execute(OfflineMutation item) async {
    switch (item.type) {
      case OfflineMutationType.productCreate:
        await _api.postJson(
          '/api/inventory/products/create',
          body: item.payload,
          timeout: const Duration(seconds: 60),
        );
      case OfflineMutationType.saleComplete:
        await _api.postJson(
          '/api/inventory/sales/complete',
          body: item.payload['request'] as Map<String, dynamic>,
          timeout: const Duration(seconds: 90),
        );
      case OfflineMutationType.purchaseComplete:
        await _api.postJson(
          '/api/inventory/purchases/complete',
          body: item.payload['request'] as Map<String, dynamic>,
          timeout: const Duration(seconds: 90),
        );
      case OfflineMutationType.mediaUpload:
        await _syncMedia(item);
    }
  }

  Future<void> _syncMedia(OfflineMutation item) async {
    final path = item.payload['localPath'] as String;
    final file = File(path);
    if (!await file.exists()) {
      throw StateError('Pending image file is missing.');
    }
    final bytes = await file.readAsBytes();
    final image = CompressedImage(
      bytes: bytes,
      mimeType: item.payload['mimeType'] as String? ?? 'image/jpeg',
      fileName: item.payload['fileName'] as String? ?? 'image.jpg',
      width: (item.payload['width'] as num?)?.round() ?? 0,
      height: (item.payload['height'] as num?)?.round() ?? 0,
    );
    final purpose = item.payload['purpose'] as String;
    final uploaded = purpose == 'product_image'
        ? await _pinata.uploadProductImage(
            businessId: item.businessId,
            image: image,
          )
        : await _pinata.uploadCustomerPhoto(
            businessId: item.businessId,
            image: image,
          );
    final collection = item.payload['collection'] as String;
    final recordId = item.payload['recordId'] as String;
    final urlField = purpose == 'product_image' ? 'imageUrl' : 'photoUrl';
    final cidField = purpose == 'product_image' ? 'imageCid' : 'photoCid';
    await _firestore
        .collection('businesses')
        .doc(item.businessId)
        .collection(collection)
        .doc(recordId)
        .set(<String, Object?>{
          urlField: uploaded.logoUrl,
          cidField: uploaded.cid,
          'imageUpdatedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
    try {
      await file.delete();
    } catch (_) {}
  }

  Future<_QueueEnvelope> _readEnvelope() => _withStorageLock(() async {
    final prefs = await SharedPreferences.getInstance();
    final envelope = _decodeEnvelope(prefs.getString(storageKey));
    if (envelope.needsWrite) {
      await prefs.setString(storageKey, jsonEncode(envelope.toJson()));
    }
    return envelope;
  });

  Future<void> _updateEnvelope(void Function(_QueueEnvelope envelope) update) =>
      _withStorageLock(() async {
        final prefs = await SharedPreferences.getInstance();
        final envelope = _decodeEnvelope(prefs.getString(storageKey));
        update(envelope);
        await prefs.setString(storageKey, jsonEncode(envelope.toJson()));
        if (!_changes.isClosed) _changes.add(null);
      });

  Future<T> _withStorageLock<T>(Future<T> Function() operation) async {
    final previous = _storageBarrier;
    final release = Completer<void>();
    _storageBarrier = release.future;
    await previous;
    try {
      return await operation();
    } finally {
      release.complete();
    }
  }

  _QueueEnvelope _decodeEnvelope(String? raw) {
    if (raw == null || raw.isEmpty) return _QueueEnvelope();
    final now = _now().toUtc();
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (error) {
      return _QueueEnvelope(
        quarantined: <OfflineMutationQuarantineEntry>[
          OfflineMutationQuarantineEntry(
            reason: 'malformed_queue',
            quarantinedAt: now,
            raw: raw,
            error: '$error',
          ),
        ],
        needsWrite: true,
      );
    }

    // Version 1 stored a bare JSON list. Entries migrate independently so a
    // damaged item cannot erase its healthy neighbours.
    if (decoded is List) {
      return _parseMutationList(decoded, needsWrite: true);
    }
    if (decoded is! Map) {
      return _quarantineWholeRaw(raw, now, 'malformed_queue');
    }
    final map = Map<String, dynamic>.from(decoded);
    if (map['version'] != envelopeVersion) {
      return _quarantineWholeRaw(raw, now, 'unsupported_version');
    }
    final rawMutations = map['mutations'];
    final rawQuarantined = map['quarantined'];
    if (rawMutations is! List ||
        (rawQuarantined != null && rawQuarantined is! List)) {
      return _quarantineWholeRaw(raw, now, 'malformed_queue');
    }

    final envelope = _parseMutationList(rawMutations);
    if (rawQuarantined is List) {
      for (final entry in rawQuarantined) {
        try {
          envelope.quarantined.add(
            OfflineMutationQuarantineEntry.fromJson(
              Map<String, dynamic>.from(entry as Map),
            ),
          );
        } catch (error) {
          envelope
            ..needsWrite = true
            ..quarantined.add(
              OfflineMutationQuarantineEntry(
                reason: 'malformed_quarantine_entry',
                quarantinedAt: now,
                raw: entry,
                error: '$error',
              ),
            );
        }
      }
    }
    return envelope;
  }

  _QueueEnvelope _parseMutationList(
    List<dynamic> rawMutations, {
    bool needsWrite = false,
  }) {
    final envelope = _QueueEnvelope(needsWrite: needsWrite);
    for (final rawMutation in rawMutations) {
      try {
        envelope.mutations.add(
          OfflineMutation.fromJson(
            Map<String, dynamic>.from(rawMutation as Map),
          ),
        );
      } catch (error) {
        envelope
          ..needsWrite = true
          ..quarantined.add(
            OfflineMutationQuarantineEntry(
              reason: 'malformed_mutation',
              quarantinedAt: _now().toUtc(),
              raw: rawMutation,
              error: '$error',
            ),
          );
      }
    }
    return envelope;
  }

  _QueueEnvelope _quarantineWholeRaw(String raw, DateTime now, String reason) =>
      _QueueEnvelope(
        quarantined: <OfflineMutationQuarantineEntry>[
          OfflineMutationQuarantineEntry(
            reason: reason,
            quarantinedAt: now,
            raw: raw,
          ),
        ],
        needsWrite: true,
      );
}

class _QueueEnvelope {
  _QueueEnvelope({
    List<OfflineMutation>? mutations,
    List<OfflineMutationQuarantineEntry>? quarantined,
    this.needsWrite = false,
  }) : mutations = mutations ?? <OfflineMutation>[],
       quarantined = quarantined ?? <OfflineMutationQuarantineEntry>[];

  final List<OfflineMutation> mutations;
  final List<OfflineMutationQuarantineEntry> quarantined;
  bool needsWrite;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'version': OfflineMutationQueue.envelopeVersion,
    'mutations': mutations.map((item) => item.toJson()).toList(),
    'quarantined': quarantined.map((item) => item.toJson()).toList(),
  };
}

final offlineMutationQueueProvider = Provider<OfflineMutationQueue>((ref) {
  final queue = OfflineMutationQueue();
  ref.onDispose(queue.dispose);
  return queue;
});

final pendingOfflineMutationsProvider = StreamProvider<List<OfflineMutation>>((
  ref,
) async* {
  final queue = ref.watch(offlineMutationQueueProvider);
  yield await queue.pending();
  await for (final _ in queue.changes) {
    yield await queue.pending();
  }
});
