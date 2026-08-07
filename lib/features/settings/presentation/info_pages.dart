import 'package:flutter/material.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/theme/app_spacing.dart';

/// Privacy policy for SabiBom.
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Privacy Policy')),
    body: ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: const <Widget>[
        _Section(
          title: 'What we collect',
          body:
              'SabiBom stores business data you enter — products, sales, customers, '
              'receipts, and account details needed to run your shop. Device tokens '
              'may be used for notifications when you allow them.',
        ),
        _Section(
          title: 'How we use it',
          body:
              'Data is used to power your inventory, sales, receipts, and Sabi '
              'assistant features. We do not sell your business records.',
        ),
        _Section(
          title: 'Images and files',
          body:
              'Business logos you upload may be stored on IPFS via Pinata so they '
              'can appear on receipts and your profile. Only images you choose to '
              'upload are sent.',
        ),
        _Section(
          title: 'Your control',
          body:
              'You can update or remove business information from the app. Sign out '
              'anytime from More. You can submit and track account or business '
              'deletion requests from Settings, Data and privacy.',
        ),
        _Section(
          title: 'Contact',
          body:
              'Questions about privacy can be sent through Help and Support in the app.',
        ),
      ],
    ),
  );
}

/// Terms of use for SabiBom.
class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Terms')),
    body: ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: const <Widget>[
        _Section(
          title: 'Using SabiBom',
          body:
              'SabiBom is a business operations tool for small shops. You are '
              'responsible for the accuracy of sales, stock, and customer records '
              'you enter.',
        ),
        _Section(
          title: 'Accounts',
          body:
              'Keep your login private. Owners are responsible for staff access on '
              'shared devices. Do not use the service for unlawful activity.',
        ),
        _Section(
          title: 'Service availability',
          body:
              'Features may change as we improve the product. We work to keep the '
              'app reliable but cannot guarantee uninterrupted access.',
        ),
        _Section(
          title: 'Data and receipts',
          body:
              'Receipts and reports are based on the data in your account. Review '
              'totals before sharing with customers.',
        ),
      ],
    ),
  );
}

/// Help center with common questions and support guidance.
class HelpSupportScreen extends StatelessWidget {
  const HelpSupportScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Help and Support')),
    body: ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: <Widget>[
        Text(
          'Quick answers for running ${AppStrings.appName} day to day.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: AppSpacing.lg),
        const _Faq(
          question: 'How do I add a product?',
          answer:
              'Open Products, tap Add, enter name, price, unit, and stock. Save to '
              'make it available at checkout.',
        ),
        const _Faq(
          question: 'How do I record a sale?',
          answer:
              'Open Sales → New sale, add items, then checkout. You can also ask '
              'Sabi to draft a sale from voice or text.',
        ),
        const _Faq(
          question: 'Why won’t my business logo upload?',
          answer:
              'Use JPEG, PNG, or WebP under about 1.5 MB after compression. Make '
              'sure you are online and signed in as the owner or manager.',
        ),
        const _Faq(
          question: 'Where do tax and currency apply?',
          answer:
              'Set them under More → Tax and Currency. They affect checkout totals '
              'and receipt display.',
        ),
        const SizedBox(height: AppSpacing.lg),
        Card(
          child: ListTile(
            leading: const Icon(Icons.support_agent_outlined),
            title: const Text('Need more help?'),
            subtitle: const Text(
              'Describe the issue from your business account email so we can look up your workspace.',
            ),
            onTap: () {
              showDialog<void>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Contact support'),
                  content: const Text(
                    'Email support with your business name, the screen you were on, '
                    'and what went wrong. Include screenshots when possible.',
                  ),
                  actions: <Widget>[
                    FilledButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('OK'),
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

/// About the SabiBom product.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('About ${AppStrings.appName}')),
    body: ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: <Widget>[
        Text(
          AppStrings.appName,
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          AppStrings.tagline,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: AppSpacing.lg),
        const Text(
          'SabiBom helps small businesses manage products, sales, customers, '
          'receipts, and day-to-day operations — with Sabi as your assistant.',
        ),
        const SizedBox(height: AppSpacing.md),
        const Text(
          'Built for shop owners who need clear stock, trustworthy receipts, and '
          'tools that work on mobile.',
        ),
        const SizedBox(height: AppSpacing.lg),
        Card(
          child: ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('Version'),
            subtitle: const Text(
              'Check your store listing for the latest build.',
            ),
          ),
        ),
      ],
    ),
  );
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.lg),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(body),
      ],
    ),
  );
}

class _Faq extends StatelessWidget {
  const _Faq({required this.question, required this.answer});

  final String question;
  final String answer;

  @override
  Widget build(BuildContext context) => Card(
    child: ExpansionTile(
      title: Text(
        question,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Align(alignment: Alignment.centerLeft, child: Text(answer)),
        ),
      ],
    ),
  );
}
