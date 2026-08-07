import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../domain/receipt_shading_background.dart';

class ShadingBackgroundRepository {
  ShadingBackgroundRepository({
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _storage = storage ?? FirebaseStorage.instance;

  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;

  CollectionReference<Map<String, dynamic>> get _backgrounds =>
      _firestore.collection('receipt_shading_backgrounds');

  Stream<List<ReceiptShadingBackground>> watchBackgrounds() {
    return _backgrounds
        .where('isActive', isEqualTo: true)
        .snapshots()
        .asyncMap((snapshot) async {
          final items = await Future.wait(
            snapshot.docs.map(_fromDoc),
          );
          final filtered = items
              .where((item) => item.imageUrl.trim().isNotEmpty)
              .toList();
          filtered.sort((a, b) {
            final byOrder = a.sortOrder.compareTo(b.sortOrder);
            if (byOrder != 0) return byOrder;
            return a.name.compareTo(b.name);
          });
          return filtered;
        });
  }

  Future<ReceiptShadingBackground> _fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final data = doc.data() ?? const <String, dynamic>{};
    final storagePath = (data['storagePath'] as String?)?.trim();
    var imageUrl = (data['imageUrl'] as String?)?.trim() ?? '';
    if (imageUrl.isEmpty && storagePath != null && storagePath.isNotEmpty) {
      try {
        imageUrl = await _storage.ref(storagePath).getDownloadURL();
      } catch (_) {
        imageUrl = '';
      }
    }

    return ReceiptShadingBackground(
      id: doc.id,
      name: (data['name'] as String?)?.trim().isNotEmpty == true
          ? (data['name'] as String).trim()
          : 'Shading',
      imageUrl: imageUrl,
      thumbnailUrl: (data['thumbnailUrl'] as String?)?.trim(),
      sortOrder: (data['sortOrder'] as num?)?.toInt() ?? 0,
      isPremium: data['isPremium'] as bool? ?? false,
    );
  }
}
