import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum RecordSyncPhase { checking, waiting, synced, failed }

class RecordSyncRequest {
  const RecordSyncRequest({
    required this.businessId,
    required this.collection,
    required this.recordId,
  });

  final String businessId;
  final String collection;
  final String recordId;

  @override
  bool operator ==(Object other) =>
      other is RecordSyncRequest &&
      other.businessId == businessId &&
      other.collection == collection &&
      other.recordId == recordId;

  @override
  int get hashCode => Object.hash(businessId, collection, recordId);
}

class RecordSyncState {
  const RecordSyncState(this.phase, {this.fromCache = false});

  final RecordSyncPhase phase;
  final bool fromCache;
}

final recordSyncFirestoreProvider = Provider<FirebaseFirestore>(
  (ref) => FirebaseFirestore.instance,
);

final recordSyncStatusProvider = StreamProvider.autoDispose
    .family<RecordSyncState, RecordSyncRequest>((ref, request) async* {
      if (request.businessId.trim().isEmpty ||
          request.collection.trim().isEmpty ||
          request.recordId.trim().isEmpty) {
        yield const RecordSyncState(RecordSyncPhase.failed);
        return;
      }

      final document = ref
          .watch(recordSyncFirestoreProvider)
          .collection('businesses')
          .doc(request.businessId)
          .collection(request.collection)
          .doc(request.recordId);
      try {
        await for (final snapshot in document.snapshots(
          includeMetadataChanges: true,
        )) {
          if (!snapshot.exists) {
            yield RecordSyncState(
              RecordSyncPhase.failed,
              fromCache: snapshot.metadata.isFromCache,
            );
            continue;
          }
          yield RecordSyncState(
            snapshot.metadata.hasPendingWrites
                ? RecordSyncPhase.waiting
                : RecordSyncPhase.synced,
            fromCache: snapshot.metadata.isFromCache,
          );
        }
      } catch (_) {
        yield const RecordSyncState(RecordSyncPhase.failed);
      }
    });

class RecordSyncStatusIcon extends ConsumerWidget {
  const RecordSyncStatusIcon({required this.request, super.key});

  final RecordSyncRequest request;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncStatus = ref.watch(recordSyncStatusProvider(request));
    final status = asyncStatus.when(
      data: (value) => value,
      loading: () => const RecordSyncState(RecordSyncPhase.checking),
      error: (_, _) => const RecordSyncState(RecordSyncPhase.failed),
    );
    final (icon, label, color) = switch (status.phase) {
      RecordSyncPhase.checking => (
        Icons.cloud_queue_outlined,
        'Checking sync status',
        Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      RecordSyncPhase.waiting => (
        Icons.cloud_upload_outlined,
        'Waiting to sync',
        Theme.of(context).colorScheme.tertiary,
      ),
      RecordSyncPhase.synced => (
        Icons.cloud_done_outlined,
        status.fromCache ? 'Synced, viewing saved data' : 'Synced',
        Colors.green,
      ),
      RecordSyncPhase.failed => (
        Icons.sync_problem_outlined,
        'Sync failed. Tap to retry',
        Theme.of(context).colorScheme.error,
      ),
    };

    return IconButton(
      onPressed: () {
        if (status.phase == RecordSyncPhase.failed) {
          ref.invalidate(recordSyncStatusProvider(request));
        }
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(label)));
      },
      tooltip: label,
      icon: Icon(icon, color: color),
    );
  }
}
