import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_spacing.dart';
import '../../auth/application/user_profile_provider.dart';
import '../data/deletion_requests_repository.dart';

final deletionRequestsRepositoryProvider = Provider<DeletionRequestsRepository>(
  (_) => DeletionRequestsRepository(),
);

final myDeletionRequestsProvider = FutureProvider<List<AccountDeletionRequest>>(
  (ref) => ref.watch(deletionRequestsRepositoryProvider).listMine(),
);

class DeletionRequestsScreen extends ConsumerStatefulWidget {
  const DeletionRequestsScreen({super.key});

  @override
  ConsumerState<DeletionRequestsScreen> createState() =>
      _DeletionRequestsScreenState();
}

class _DeletionRequestsScreenState
    extends ConsumerState<DeletionRequestsScreen> {
  final _reason = TextEditingController();
  var _scope = 'account';
  var _submitting = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final requests = ref.watch(myDeletionRequestsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Data deletion requests')),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(myDeletionRequestsProvider.future),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.md,
            96,
          ),
          children: [
            Text(
              'Request deletion of your account, business, or selected data. Requests are reviewed before any permanent action.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.lg),
            DropdownButtonFormField<String>(
              initialValue: _scope,
              decoration: const InputDecoration(
                labelText: 'What should be deleted?',
              ),
              items: const [
                DropdownMenuItem(value: 'account', child: Text('My account')),
                DropdownMenuItem(
                  value: 'business',
                  child: Text('My business data'),
                ),
                DropdownMenuItem(
                  value: 'specific_data',
                  child: Text('Specific data'),
                ),
                DropdownMenuItem(value: 'other', child: Text('Other')),
              ],
              onChanged: _submitting
                  ? null
                  : (value) => setState(() => _scope = value ?? 'account'),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _reason,
              minLines: 3,
              maxLines: 6,
              maxLength: 1200,
              decoration: const InputDecoration(
                labelText: 'Reason and details',
                hintText: 'Tell us what you want removed and why.',
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            FilledButton.icon(
              onPressed: _submitting ? null : _submit,
              icon: _submitting
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.delete_outline),
              label: const Text('Submit deletion request'),
            ),
            const SizedBox(height: AppSpacing.xl),
            Text(
              'Your requests',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AppSpacing.sm),
            requests.when(
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
              ),
              error: (_, _) => const Card(
                child: ListTile(
                  title: Text('Could not load your requests.'),
                  subtitle: Text('Pull down to try again.'),
                ),
              ),
              data: (items) => items.isEmpty
                  ? const Card(
                      child: ListTile(
                        title: Text('No deletion requests'),
                        subtitle: Text(
                          'Submitted requests and their review status will appear here.',
                        ),
                      ),
                    )
                  : Column(
                      children: items.map(_requestCard).toList(growable: false),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _requestCard(AccountDeletionRequest request) => Card(
    child: ListTile(
      leading: const Icon(Icons.policy_outlined),
      title: Text(request.status.replaceAll('_', ' ')),
      subtitle: Text(
        [
          request.scope.replaceAll('_', ' '),
          if (request.requestedAt != null)
            DateFormat('d MMM yyyy, HH:mm').format(request.requestedAt!),
          if (request.safeNotes?.isNotEmpty == true) request.safeNotes!,
        ].join('\n'),
      ),
    ),
  );

  Future<void> _submit() async {
    final reason = _reason.text.trim();
    if (reason.length < 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter at least 5 characters explaining your request.'),
        ),
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      final businessId = ref
          .read(currentUserProfileProvider)
          .asData
          ?.value
          ?.activeBusinessId;
      await ref
          .read(deletionRequestsRepositoryProvider)
          .create(scope: _scope, reason: reason, businessId: businessId);
      _reason.clear();
      ref.invalidate(myDeletionRequestsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Deletion request submitted for review.'),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not submit the request. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}
