import 'package:flutter/material.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/theme/app_spacing.dart';

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
              'SabiBom processes the account and business data you enter, including '
              'branches, products or services, inventory, customers, suppliers, '
              'sales, purchases, expenses, receipts, staff access, and reports. '
              'Device tokens are used for notifications when you allow them.',
        ),
        _Section(
          title: 'How we use it',
          body:
              'Data powers your business workflows and Sabi assistant, secures the '
              'service, provides support, and improves reliability. We do not sell '
              'your personal information or business records.',
        ),
        _Section(
          title: 'Optional device access',
          body:
              'Camera, photo, file, and microphone data are accessed only when you '
              'choose features such as image capture, attachments, barcode workflows, '
              'or Sabi voice input. You can revoke optional permissions in Android settings.',
        ),
        _Section(
          title: 'Diagnostics and service providers',
          body:
              'SabiBom uses managed providers for authentication, cloud data, files, '
              'app verification, notifications, analytics, crash reporting, performance '
              'monitoring, hosting, and supported AI features. Limited device and usage '
              'diagnostics help us secure and improve the service.',
        ),
        _Section(
          title: 'Retention and deletion',
          body:
              'We retain data while needed to operate your account. Approved deletion '
              'requests remove or anonymize covered data, except records temporarily '
              'retained for security, fraud prevention, accounting, disputes, or legal '
              'obligations. Submit requests from Settings, Data and privacy, or visit '
              'https://sabibom.com/delete-account.',
        ),
        _Section(
          title: 'Contact',
          body:
              'Questions can be sent to support@sabibom.com. The complete policy is '
              'available at https://sabibom.com/privacy.',
        ),
      ],
    ),
  );
}

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
              'SabiBom is a business operations tool. You are responsible for the '
              'accuracy of sales, stock, customer, supplier, expense, and other '
              'records you enter and for using the service lawfully.',
        ),
        _Section(
          title: 'Accounts and staff',
          body:
              'Keep your login private. Business owners are responsible for staff '
              'roles, permissions, and branch access. Do not attempt to bypass '
              'security or access another business without authorization.',
        ),
        _Section(
          title: 'Service availability',
          body:
              'Features may change as the product improves. We work to keep SabiBom '
              'reliable but cannot guarantee uninterrupted or error-free access.',
        ),
        _Section(
          title: 'Records and advice',
          body:
              'Receipts and reports depend on your account data. Review important '
              'totals before relying on them. SabiBom is not a bank, accountant, tax '
              'adviser, lawyer, or auditor.',
        ),
        _Section(
          title: 'Sabi assistance',
          body:
              'AI-assisted responses may be incomplete or incorrect. Review proposed '
              'actions, totals, and reports before relying on them or saving records.',
        ),
        _Section(
          title: 'Plans and payments',
          body:
              'Features may depend on a free, trial, complimentary, or paid plan. Any '
              'paid Android subscription offered inside the app will use the payment '
              'terms presented through Google Play.',
        ),
        _Section(
          title: 'Contact',
          body:
              'Questions can be sent to support@sabibom.com. The complete terms are '
              'available at https://sabibom.com/terms.',
        ),
      ],
    ),
  );
}

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
              'Open Sales, select New sale, add items, then checkout. You can also '
              'ask Sabi to draft a sale from voice or text.',
        ),
        const _Faq(
          question: 'Why will my business logo not upload?',
          answer:
              'Use JPEG, PNG, or WebP under about 1.5 MB after compression. Make '
              'sure you are online and signed in as the owner or manager.',
        ),
        const _Faq(
          question: 'Where do tax and currency apply?',
          answer:
              'Set them under More, Tax and Currency. They affect checkout totals '
              'and receipt display.',
        ),
        const SizedBox(height: AppSpacing.lg),
        Card(
          child: ListTile(
            leading: const Icon(Icons.support_agent_outlined),
            title: const Text('Need more help?'),
            subtitle: const Text(
              'Describe the issue from your business account email so support can identify your workspace.',
            ),
            onTap: () {
              showDialog<void>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Contact support'),
                  content: const Text(
                    'Email support@sabibom.com with your business name, the screen '
                    'you were on, and what went wrong. Include screenshots when '
                    'possible. Never send passwords, PINs, private keys, or payment credentials.',
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
          'SabiBom helps small businesses manage products or services, sales, '
          'customers, receipts, branches, and day-to-day operations with Sabi as an assistant.',
        ),
        const SizedBox(height: AppSpacing.lg),
        const Card(
          child: ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('Version'),
            subtitle: Text('1.0.0'),
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
