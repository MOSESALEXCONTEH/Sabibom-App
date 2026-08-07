import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sabibom/features/branches/application/branch_query_error.dart';

void main() {
  test('missing index maps to a safe branch preparation message', () {
    final view = branchQueryErrorView(
      FirebaseException(
        plugin: 'cloud_firestore',
        code: 'failed-precondition',
        message: 'The query requires an index.',
      ),
      queryName: 'sales',
      businessId: 'business-1',
      branchId: 'east',
      limit: 25,
    );

    expect(view.message, contains('branch view is still being prepared'));
    expect(view.message, isNot(contains('Firebase')));
  });

  test('permission denied maps to a safe branch permission message', () {
    final view = branchQueryErrorView(
      FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'),
      queryName: 'purchases',
      businessId: 'business-1',
      branchId: 'east',
      limit: 100,
    );

    expect(view.message, 'You do not have permission to view this branch.');
  });

  test('sales and purchase index configuration matches branch queries', () {
    final root =
        jsonDecode(File('firestore.indexes.json').readAsStringSync())
            as Map<String, dynamic>;
    final indexes = (root['indexes'] as List<dynamic>)
        .cast<Map<String, dynamic>>();

    expect(_hasBranchCreatedAtIndex(indexes, 'sales'), isTrue);
    expect(_hasBranchCreatedAtIndex(indexes, 'purchases'), isTrue);
  });
}

bool _hasBranchCreatedAtIndex(
  List<Map<String, dynamic>> indexes,
  String collectionGroup,
) {
  return indexes.any((index) {
    if (index['collectionGroup'] != collectionGroup ||
        index['queryScope'] != 'COLLECTION') {
      return false;
    }
    final fields = (index['fields'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    return fields.length == 2 &&
        fields[0]['fieldPath'] == 'branchId' &&
        fields[0]['order'] == 'ASCENDING' &&
        fields[1]['fieldPath'] == 'createdAt' &&
        fields[1]['order'] == 'DESCENDING';
  });
}
