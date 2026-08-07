import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../app/router.dart';
import '../../../core/services/image_compression_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../business_profile/services/pinata_upload_service.dart';
import '../../dashboard/application/dashboard_providers.dart';
import '../../setup/application/setup_providers.dart';
import '../data/feedback_repository.dart';
import '../domain/faq_catalog.dart';

class HelpHomeScreen extends StatelessWidget {
  const HelpHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Help and Feedback')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          Text(
            'Get answers, send feedback, or report a problem. Basic help works offline.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.lg),
          _tile(
            context,
            Icons.menu_book_outlined,
            'FAQ',
            'Search common questions',
            () => context.pushNamed(AppRouteNames.helpFaq),
          ),
          _tile(
            context,
            Icons.feedback_outlined,
            'Send feedback',
            'Bug, idea, or calculation concern',
            () => context.pushNamed(AppRouteNames.helpFeedback),
          ),
          _tile(
            context,
            Icons.report_problem_outlined,
            'Report a problem',
            'Something broke while you worked',
            () => context.pushNamed(AppRouteNames.helpReportProblem),
          ),
          _tile(
            context,
            Icons.support_agent_outlined,
            'Contact',
            'How to reach support',
            () => context.pushNamed(AppRouteNames.helpContact),
          ),
          Consumer(
            builder: (context, ref, _) {
              return _tile(
                context,
                Icons.checklist_outlined,
                'Restore setup checklist',
                'Show the first-business checklist again',
                () async {
                  await ref.read(setupChecklistServiceProvider).restore();
                  ref.invalidate(setupChecklistProvider);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Setup checklist restored on Home.'),
                      ),
                    );
                    context.go(AppRoutes.home);
                  }
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _tile(
    BuildContext context,
    IconData icon,
    String title,
    String subtitle,
    VoidCallback onTap,
  ) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: DecoratedBox(
          decoration: BoxDecoration(
            color: context.brandTint,
            borderRadius: BorderRadius.circular(AppRadii.chip),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Icon(
              icon,
              size: 20,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle),
        trailing: Icon(Icons.chevron_right, color: context.mutedTextColor),
        onTap: onTap,
      ),
    );
  }
}

class HelpFaqScreen extends StatefulWidget {
  const HelpFaqScreen({super.key});

  @override
  State<HelpFaqScreen> createState() => _HelpFaqScreenState();
}

class _HelpFaqScreenState extends State<HelpFaqScreen> {
  final _query = TextEditingController();
  String? _category;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var items = FaqCatalog.search(_query.text);
    if (_category != null) {
      items = items.where((i) => i.category == _category).toList();
    }
    return Scaffold(
      appBar: AppBar(title: const Text('FAQ')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: TextField(
              controller: _query,
              decoration: const InputDecoration(
                hintText: 'Search help',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              children: [
                FilterChip(
                  label: const Text('All'),
                  selected: _category == null,
                  onSelected: (_) => setState(() => _category = null),
                ),
                ...FaqCatalog.categories.map(
                  (c) => Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: FilterChip(
                      label: Text(c),
                      selected: _category == c,
                      onSelected: (_) => setState(() => _category = c),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(AppSpacing.md),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                return Card(
                  child: ExpansionTile(
                    title: Text(
                      item.question,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(item.category),
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(item.answer),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class HelpContactScreen extends StatelessWidget {
  const HelpContactScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Contact')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: const [
          Text(
            'Email support with your business name, the screen you were on, '
            'and what went wrong. Include a screenshot only if it does not show '
            'private customer details.',
          ),
          SizedBox(height: AppSpacing.md),
          Text(
            'Prefer in-app feedback when possible — it attaches safe version '
            'details you can review before sending.',
          ),
        ],
      ),
    );
  }
}

class HelpFeedbackScreen extends ConsumerStatefulWidget {
  const HelpFeedbackScreen({super.key, this.initialCategory});

  final FeedbackCategory? initialCategory;

  @override
  ConsumerState<HelpFeedbackScreen> createState() => _HelpFeedbackScreenState();
}

class _HelpFeedbackScreenState extends ConsumerState<HelpFeedbackScreen> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  late FeedbackCategory _category;
  SafeDiagnostics? _diagnostics;
  XFile? _image;
  var _includeDiagnostics = true;
  var _submitting = false;

  @override
  void initState() {
    super.initState();
    _category = widget.initialCategory ?? FeedbackCategory.bug;
    SafeDiagnostics.collect(currentRoute: '/help/feedback').then((d) {
      if (mounted) setState(() => _diagnostics = d);
    });
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.initialCategory == FeedbackCategory.bug
              ? 'Report a problem'
              : 'Send feedback',
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          DropdownButtonFormField<FeedbackCategory>(
            initialValue: _category,
            decoration: const InputDecoration(labelText: 'Category'),
            items: FeedbackCategory.values
                .map(
                  (c) => DropdownMenuItem(value: c, child: Text(c.label)),
                )
                .toList(),
            onChanged: (v) {
              if (v != null) setState(() => _category = v);
            },
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _title,
            decoration: const InputDecoration(labelText: 'Title'),
            maxLength: 120,
          ),
          TextField(
            controller: _description,
            decoration: const InputDecoration(labelText: 'Description'),
            maxLines: 5,
            maxLength: 2000,
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Include safe diagnostics'),
            subtitle: Text(
              _diagnostics == null
                  ? 'Loading…'
                  : 'Version ${_diagnostics!.appVersion} (${_diagnostics!.buildNumber}) · ${_diagnostics!.platform}',
            ),
            value: _includeDiagnostics,
            onChanged: (v) => setState(() => _includeDiagnostics = v),
          ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            onPressed: _pickImage,
            icon: const Icon(Icons.image_outlined),
            label: Text(_image == null ? 'Add screenshot' : 'Change screenshot'),
          ),
          if (_image != null) ...[
            const SizedBox(height: 8),
            Text(
              'Review your screenshot and make sure it does not contain private '
              'customer or business information.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Text('Selected: ${_image!.name}'),
          ],
          const SizedBox(height: AppSpacing.lg),
          FilledButton(
            onPressed: _submitting ? null : _submit,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
            child: _submitting
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Submit'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickImage() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      imageQuality: 75,
    );
    if (file == null) return;
    setState(() => _image = file);
  }

  Future<void> _submit() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    if (_title.text.trim().length < 3 || _description.text.trim().length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a clear title and description.'),
        ),
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      final active = ref.read(activeBusinessProvider).asData?.value;
      final businessId =
          active is ActiveBusinessData ? active.business.businessId : null;
      String? attachmentUrl;
      String? attachmentCid;
      var screenshotNote = '';
      if (_image != null) {
        if (businessId != null) {
          try {
            final bytes = await _image!.readAsBytes();
            final compressed = await ImageCompressionService().prepareLogo(
              sourceBytes: bytes,
              fileName: _image!.name,
              mimeType: _image!.mimeType,
            );
            final uploaded =
                await ref.read(pinataUploadServiceProvider).uploadFeedbackAttachment(
                      businessId: businessId,
                      image: compressed,
                    );
            attachmentUrl = uploaded.logoUrl;
            attachmentCid = uploaded.cid;
          } catch (_) {
            screenshotNote =
                '\n\n[Screenshot selected (${_image!.name}) but upload failed. Text feedback was still saved.]';
          }
        } else {
          screenshotNote =
              '\n\n[Screenshot selected (${_image!.name}) but no active business was available for upload.]';
        }
      }
      await FeedbackRepository().submit(
        userId: uid,
        category: _category,
        title: _title.text,
        description: _description.text + screenshotNote,
        businessId: businessId,
        diagnostics: _includeDiagnostics ? _diagnostics : null,
        attachmentUrl: attachmentUrl,
        attachmentCid: attachmentCid,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Thank you. Your feedback was sent.')),
      );
      context.pop();
    } catch (error) {
      if (!mounted) return;
      final detail = error is FirebaseException
          ? (error.message?.trim().isNotEmpty == true
              ? error.message!
              : error.code)
          : error.toString();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not send feedback: $detail')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}

class AboutSabiBomScreen extends StatelessWidget {
  const AboutSabiBomScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('About SabiBom')),
      body: FutureBuilder<PackageInfo>(
        future: PackageInfo.fromPlatform(),
        builder: (context, snap) {
          final version = snap.data == null
              ? '…'
              : 'Version ${snap.data!.version} (${snap.data!.buildNumber})';
          return ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              Text(
                'SabiBom',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 8),
              Text(version),
              const SizedBox(height: AppSpacing.lg),
              const Text(
                'SabiBom helps you record sales, create receipts, track stock, '
                'manage expenses and understand your business.',
              ),
              const SizedBox(height: AppSpacing.md),
              const Text(
                'Sabi helps you prepare business records and understand verified '
                'business information. Sabi does not replace an accountant and '
                'does not make decisions automatically.',
              ),
              const SizedBox(height: AppSpacing.lg),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Privacy Policy'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(AppRoutes.privacy),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Terms'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(AppRoutes.terms),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Help and Feedback'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.pushNamed(AppRouteNames.help),
              ),
            ],
          );
        },
      ),
    );
  }
}
