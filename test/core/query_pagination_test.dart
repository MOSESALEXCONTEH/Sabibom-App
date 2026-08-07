import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sabibom/core/firestore/query_pagination.dart';

void main() {
  test('reads every document across multiple Firestore pages', () async {
    final firestore = FakeFirebaseFirestore();
    final collection = firestore.collection('records');
    for (var index = 0; index < 23; index++) {
      await collection.doc(index.toString().padLeft(3, '0')).set({
        'index': index,
      });
    }

    final documents = await readAllQueryPages(
      collection.orderBy('index'),
      pageSize: 5,
    );

    expect(documents, hasLength(23));
    expect(
      documents.map((doc) => doc.data()['index']),
      orderedEquals(List.generate(23, (index) => index)),
    );
  });

  test('returns an empty list for an empty query', () async {
    final firestore = FakeFirebaseFirestore();

    final documents = await readAllQueryPages(
      firestore.collection('records'),
      pageSize: 5,
    );

    expect(documents, isEmpty);
  });
}
