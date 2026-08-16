import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/business_profile/services/pinata_upload_service.dart';
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
  });

  factory OfflineMutation.fromJson(Map<String, dynamic> json) =>
      OfflineMutation(
        id: json['id'] as String,
        type: OfflineMutationType.values.byName(json['type'] as String),
        userId: json['userId'] as String,
        businessId: json['businessId'] as String,
        payload: Map<String, dynamic>.from(json['payload'] as Map),
        createdAt: DateTime.parse(json['createdAt'] as String),
        lastError: json['lastError'] as String?,
      );

  final String id;
  final OfflineMutationType type;
  final String userId;
  final String businessId;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final String? lastError;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'type': type.name,
    'userId': userId,
    'businessId': businessId,
    'payload': payload,
    'createdAt': createdAt.toIso8601String(),
    if (lastError != null) 'lastError': lastError,
  };

  OfflineMutation copyWith({String? lastError}) => OfflineMutation(
    id: id,
    type: type,
    userId: userId,
    businessId: businessId,
    payload: payload,
    createdAt: createdAt,
    lastError: lastError,
  );
}

class OfflineMutationQueue {
  OfflineMutationQueue({
    FirebaseAuth? auth,
    String? Function()? currentUserId,
    FirebaseFirestore? firestore,
    AuthenticatedApiClient? apiClient,
    PinataUploadService? pinata,
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
       _pinataOverride = pinata;

  static const _storageKey = 'sabibom_offline_mutations_v1';
  final String? Function() _currentUserId;
  final FirebaseFirestore? _firestoreOverride;
  final AuthenticatedApiClient? _apiOverride;
  final PinataUploadService? _pinataOverride;
  FirebaseFirestore get _firestore =>
      _firestoreOverride ?? FirebaseFirestore.instance;
  AuthenticatedApiClient get _api => _apiOverride ?? AuthenticatedApiClient();
  PinataUploadService get _pinata =>
      _pinataOverride ?? FirebasePinataUploadService();
  final _changes = StreamController<void>.broadcast();
  bool _syncing = false;

  Stream<void> get changes => _changes.stream;

  void dispose() => _changes.close();

  Future<List<OfflineMutation>> pending({String? businessId}) async {
    final uid = _currentUserId();
    if (uid == null) return const <OfflineMutation>[];
    final all = await _readAll();
    return all
        .where(
          (item) =>
              item.userId == uid &&
              (businessId == null || item.businessId == businessId),
        )
        .toList(growable: false);
  }

  Future<void> enqueue({
    required String id,
    required OfflineMutationType type,
    required String businessId,
    required Map<String, dynamic> payload,
  }) async {
    final uid = _currentUserId();
    if (uid == null) throw StateError('A signed-in user is required.');
    final all = await _readAll();
    final item = OfflineMutation(
      id: id,
      type: type,
      userId: uid,
      businessId: businessId,
      payload: payload,
      createdAt: DateTime.now().toUtc(),
    );
    final index = all.indexWhere((candidate) => candidate.id == id);
    if (index < 0) {
      all.add(item);
    } else {
      all[index] = item;
    }
    await _writeAll(all);
  }

  Future<void> syncPending() async {
    if (_syncing || _currentUserId() == null) return;
    _syncing = true;
    try {
      final uid = _currentUserId()!;
      final snapshot = await _readAll();
      for (final item in List<OfflineMutation>.from(snapshot)) {
        if (item.userId != uid) continue;
        try {
          await _execute(item);
          final latest = await _readAll();
          latest.removeWhere((candidate) => candidate.id == item.id);
          await _writeAll(latest);
        } catch (error) {
          final latest = await _readAll();
          final index = latest.indexWhere(
            (candidate) => candidate.id == item.id,
          );
          if (index >= 0) latest[index] = item.copyWith(lastError: '$error');
          await _writeAll(latest);
          // A product image depends on its preceding product creation.
          // Other independent writes may continue syncing.
          if (item.type == OfflineMutationType.productCreate) break;
        }
      }
    } finally {
      _syncing = false;
    }
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

  Future<List<OfflineMutation>> _readAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) return <OfflineMutation>[];
    try {
      return (jsonDecode(raw) as List)
          .map(
            (item) => OfflineMutation.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList();
    } catch (_) {
      return <OfflineMutation>[];
    }
  }

  Future<void> _writeAll(List<OfflineMutation> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _storageKey,
      jsonEncode(items.map((item) => item.toJson()).toList()),
    );
    _changes.add(null);
  }
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
