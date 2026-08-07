import 'package:cloud_firestore/cloud_firestore.dart';

/// Reads a Firestore query completely in bounded pages.
///
/// This is intended for correctness-sensitive calculations that cannot use a
/// Firestore aggregate because they still need to inspect each document.
Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> readAllQueryPages(
  Query<Map<String, dynamic>> query, {
  int pageSize = 500,
}) async {
  assert(pageSize > 0);
  final documents = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
  Query<Map<String, dynamic>> pageQuery = query.limit(pageSize);

  while (true) {
    final snapshot = await pageQuery.get();
    documents.addAll(snapshot.docs);
    if (snapshot.docs.length < pageSize) break;
    pageQuery = query.startAfterDocument(snapshot.docs.last).limit(pageSize);
  }

  return documents;
}
