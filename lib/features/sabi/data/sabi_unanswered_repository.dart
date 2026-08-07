import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// One unanswered Sabi ask saved for training review.
class SabiUnansweredAsk {
  const SabiUnansweredAsk({
    required this.id,
    required this.businessId,
    required this.question,
    required this.status,
    required this.count,
    this.userId,
    this.reply,
    this.source,
    this.lastAskedAt,
    this.createdAt,
  });

  factory SabiUnansweredAsk.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snap,
  ) {
    final data = snap.data() ?? const <String, dynamic>{};
    return SabiUnansweredAsk(
      id: snap.id,
      businessId: data['businessId'] as String? ?? '',
      userId: data['userId'] as String?,
      question: data['question'] as String? ?? '',
      reply: data['reply'] as String?,
      source: data['source'] as String?,
      status: data['status'] as String? ?? 'new',
      count: (data['count'] as num?)?.toInt() ?? 1,
      lastAskedAt: (data['lastAskedAt'] as Timestamp?)?.toDate(),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  final String id;
  final String businessId;
  final String? userId;
  final String question;
  final String? reply;
  final String? source;
  final String status;
  final int count;
  final DateTime? lastAskedAt;
  final DateTime? createdAt;
}

/// Saves Sabi questions that could not be answered from verified records.
///
/// Stored for later review / training improvements:
/// - `sabi_unanswered/{id}` (global training inbox)
/// - `businesses/{businessId}/sabi_unanswered/{id}` (per business)
class SabiUnansweredRepository {
  SabiUnansweredRepository({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _db = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  /// Records an unanswered ask. Safe to call fire-and-forget; never throws
  /// into the chat UI.
  Future<void> record({
    required String businessId,
    required String question,
    String? reply,
    String? replyLanguage,
    String? source,
  }) async {
    final trimmed = question.trim();
    if (businessId.trim().isEmpty || trimmed.length < 3) return;
    final uid = _auth.currentUser?.uid;
    if (uid == null || uid.isEmpty) return;

    final normalized = normalizeQuestion(trimmed);
    final id = docId(businessId: businessId, normalized: normalized);
    final payload = <String, Object?>{
      'id': id,
      'businessId': businessId,
      'userId': uid,
      'question': trimmed,
      'questionNormalized': normalized,
      'reply': reply?.trim().isEmpty == true ? null : reply?.trim(),
      'replyLanguage': replyLanguage,
      'source': source ?? 'ask',
      'status': 'new', // new | reviewed | trained | ignored
      'count': FieldValue.increment(1),
      'lastAskedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    try {
      final ref = _db.collection('sabi_unanswered').doc(id);
      final exists = (await ref.get()).exists;
      await ref.set({
        ...payload,
        if (!exists) 'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}

    try {
      final ref = _db
          .collection('businesses')
          .doc(businessId)
          .collection('sabi_unanswered')
          .doc(id);
      final exists = (await ref.get()).exists;
      await ref.set({
        ...payload,
        if (!exists) 'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  /// Live list for a business (newest first).
  Stream<List<SabiUnansweredAsk>> watchForBusiness(
    String businessId, {
    int limit = 100,
  }) {
    if (businessId.trim().isEmpty) {
      return Stream.value(const <SabiUnansweredAsk>[]);
    }
    return _db
        .collection('businesses')
        .doc(businessId)
        .collection('sabi_unanswered')
        .orderBy('lastAskedAt', descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (snap) => snap.docs.map(SabiUnansweredAsk.fromFirestore).toList(),
        );
  }

  /// One-shot fetch for a business training inbox (no composite index needed).
  Future<List<SabiUnansweredAsk>> listForBusiness(
    String businessId, {
    int limit = 200,
  }) async {
    if (businessId.trim().isEmpty) return const <SabiUnansweredAsk>[];
    final snap = await _db
        .collection('businesses')
        .doc(businessId)
        .collection('sabi_unanswered')
        .orderBy('lastAskedAt', descending: true)
        .limit(limit)
        .get();
    return snap.docs.map(SabiUnansweredAsk.fromFirestore).toList();
  }

  /// Global inbox filtered in memory (avoids composite-index setup).
  Future<List<SabiUnansweredAsk>> listGlobal({
    String? businessId,
    String? status,
    int limit = 200,
  }) async {
    Query<Map<String, dynamic>> query = _db
        .collection('sabi_unanswered')
        .orderBy('lastAskedAt', descending: true)
        .limit(limit * 2);
    final snap = await query.get();
    var rows = snap.docs.map(SabiUnansweredAsk.fromFirestore).toList();
    if (businessId != null && businessId.trim().isNotEmpty) {
      rows = rows.where((r) => r.businessId == businessId).toList();
    }
    if (status != null && status.trim().isNotEmpty) {
      rows = rows.where((r) => r.status == status).toList();
    }
    if (rows.length > limit) rows = rows.take(limit).toList();
    return rows;
  }

  Future<void> markStatus({
    required String businessId,
    required String askId,
    required String status,
  }) async {
    final patch = <String, Object?>{
      'status': status,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    try {
      await _db.collection('sabi_unanswered').doc(askId).set(
            patch,
            SetOptions(merge: true),
          );
    } catch (_) {}
    try {
      await _db
          .collection('businesses')
          .doc(businessId)
          .collection('sabi_unanswered')
          .doc(askId)
          .set(patch, SetOptions(merge: true));
    } catch (_) {}
  }

  /// Same normalization as the Vercel API trainer inbox.
  static String normalizeQuestion(String question) {
    return question
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Same id scheme as `vercel-api` (`sha1(businessId::normalized).slice(0,24)`).
  static String docId({
    required String businessId,
    required String normalized,
  }) {
    final digest = sha1.convert(utf8.encode('$businessId::$normalized'));
    return digest.toString().substring(0, 24);
  }
}
