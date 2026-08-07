import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../domain/receipt_template.dart';

class ReceiptTemplateRepository {
  ReceiptTemplateRepository({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  CollectionReference<Map<String, dynamic>> _templates(String businessId) =>
      _firestore
          .collection('businesses')
          .doc(businessId)
          .collection('receipt_templates');

  Stream<List<ReceiptTemplate>> watchTemplates(String businessId) {
    if (businessId.trim().isEmpty) {
      return Stream.value(const <ReceiptTemplate>[]);
    }
    return _templates(businessId).snapshots().map((snapshot) {
      final saved = snapshot.docs
          .map((doc) => ReceiptTemplate.fromMap(doc.id, doc.data()))
          .toList();
      return _mergeBuiltIns(businessId, saved);
    });
  }

  List<ReceiptTemplate> _mergeBuiltIns(
    String businessId,
    List<ReceiptTemplate> saved,
  ) {
    final result = List<ReceiptTemplate>.from(saved);
    for (final type in ReceiptTemplateType.values) {
      final hasType = saved.any((item) => item.templateType == type);
      if (!hasType) {
        result.add(ReceiptTemplate.builtIn(type: type, businessId: businessId));
      }
    }
    result.sort((a, b) {
      if (a.isDefault != b.isDefault) {
        return a.isDefault ? -1 : 1;
      }
      return a.name.compareTo(b.name);
    });
    return result;
  }

  Future<ReceiptTemplate> getDefaultTemplate(
    String businessId, {
    String? preferredId,
  }) async {
    final preferred = preferredId?.trim();
    if (preferred != null &&
        preferred.isNotEmpty &&
        !preferred.startsWith('builtin_')) {
      final doc = await _templates(businessId).doc(preferred).get();
      if (doc.exists && doc.data() != null) {
        return ReceiptTemplate.fromMap(doc.id, doc.data()!);
      }
    }
    final snap = await _templates(
      businessId,
    ).where('isDefault', isEqualTo: true).limit(1).get();
    if (snap.docs.isNotEmpty) {
      final doc = snap.docs.first;
      return ReceiptTemplate.fromMap(doc.id, doc.data());
    }
    return ReceiptTemplate.builtIn(
      type: ReceiptTemplateType.luxury,
      businessId: businessId,
    );
  }

  Future<String> saveTemplate(
    ReceiptTemplate template, {
    bool forceNew = false,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('unauthenticated');
    }
    final isNew =
        forceNew || template.id.startsWith('builtin_') || template.id.isEmpty;
    final ref = isNew
        ? _templates(template.businessId).doc()
        : _templates(template.businessId).doc(template.id);

    final batch = _firestore.batch();
    if (template.isDefault) {
      final existing = await _templates(template.businessId).get();
      for (final doc in existing.docs) {
        batch.set(doc.reference, <String, Object?>{
          'isDefault': false,
        }, SetOptions(merge: true));
      }
      batch.set(
        _firestore.collection('businesses').doc(template.businessId),
        {
          'defaultReceiptTemplateId': ref.id,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    }

    batch.set(ref, {
      ...template.toMap(),
      'createdBy': user.uid,
      if (isNew) 'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await batch.commit();
    return ref.id;
  }

  Future<void> deleteTemplate(String businessId, String templateId) async {
    if (templateId.startsWith('builtin_')) return;
    await _templates(businessId).doc(templateId).delete();
  }
}
