/// Local FAQ content — available offline.
class FaqItem {
  const FaqItem({
    required this.category,
    required this.question,
    required this.answer,
    this.routeName,
  });

  final String category;
  final String question;
  final String answer;
  final String? routeName;
}

abstract final class FaqCatalog {
  static const categories = <String>[
    'Getting Started',
    'Sales and Receipts',
    'Products and Stock',
    'Customers and Credit',
    'Expenses',
    'Suppliers and Purchases',
    'Team and Permissions',
    'Sabi AI',
    'End of Day',
    'Notifications',
    'Backup and Import',
    'Account and Security',
  ];

  static const items = <FaqItem>[
    FaqItem(
      category: 'Getting Started',
      question: 'How do I set up my business?',
      answer:
          'After you create an account, choose Set Up Now and enter your business name, contact details, currency and tax settings. You can finish later from Business Profile.',
      routeName: 'settingsBusiness',
    ),
    FaqItem(
      category: 'Getting Started',
      question: 'What is Demo Business?',
      answer:
          'Demo Business loads sample data only so you can explore SabiBom safely. It is labeled clearly and stays separate from your real business.',
    ),
    FaqItem(
      category: 'Sales and Receipts',
      question: 'How do I record a sale?',
      answer:
          'Open Sales, start a new sale, add products, choose a payment method, then complete the sale. You can download or share a receipt afterwards.',
      routeName: 'newSale',
    ),
    FaqItem(
      category: 'Products and Stock',
      question: 'Why did stock not change?',
      answer:
          'Stock only changes for products with stock tracking enabled. Custom items and untracked products do not reduce inventory.',
      routeName: 'products',
    ),
    FaqItem(
      category: 'Customers and Credit',
      question: 'How does customer credit work?',
      answer:
          'When a sale leaves a balance due, the customer balance increases. Record a customer payment to reduce it. Staff need permission to view balances.',
      routeName: 'customers',
    ),
    FaqItem(
      category: 'Expenses',
      question: 'Can I void an expense?',
      answer:
          'Yes, if your role allows it. Voiding reverses the expense from reports. Keep a clear reason.',
      routeName: 'expenses',
    ),
    FaqItem(
      category: 'Suppliers and Purchases',
      question: 'How do purchases update stock?',
      answer:
          'Completed purchases increase stock for tracked products and may create a supplier balance when unpaid.',
      routeName: 'purchases',
    ),
    FaqItem(
      category: 'Team and Permissions',
      question: 'Why can’t a cashier see profit?',
      answer:
          'Profit requires the view profit permission. Owners and accountants usually have it; cashiers do not by default.',
      routeName: 'team',
    ),
    FaqItem(
      category: 'Sabi AI',
      question: 'Does Sabi create sales automatically?',
      answer:
          'No. Sabi prepares drafts from what you say. You must review and confirm before anything is saved. Sabi does not invent financial totals.',
    ),
    FaqItem(
      category: 'End of Day',
      question: 'What is End of Day?',
      answer:
          'End of Day compares expected physical cash with the cash you counted. '
          'Expected cash uses opening cash plus cash sales and cash customer payments, '
          'minus cash expenses and cash supplier payments. Mobile Money, card and bank '
          'transfer are excluded. Finalize when the drawer matches, or note a shortage or surplus.',
      routeName: 'endOfDay',
    ),
    FaqItem(
      category: 'Notifications',
      question: 'Why do I see duplicate stock alerts?',
      answer:
          'You should not. Alerts use stable keys so the same stock cycle does not notify repeatedly. After you restock, a later drop can create a new alert.',
      routeName: 'notifications',
    ),
    FaqItem(
      category: 'Backup and Import',
      question: 'How do I back up my data?',
      answer:
          'Open More → Backup and Restore (owners/managers). Create a JSON backup and '
          'share or save the file somewhere safe. Restore creates a new business and '
          'never overwrites your current one. Secrets and device tokens are not included.',
      routeName: 'backup',
    ),
    FaqItem(
      category: 'Account and Security',
      question: 'How do I delete my account?',
      answer:
          'Contact support from Help and describe the account email and business name. Account deletion removes access according to our privacy policy.',
      routeName: 'helpContact',
    ),
  ];

  static List<FaqItem> search(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return items;
    return items
        .where(
          (i) =>
              i.question.toLowerCase().contains(q) ||
              i.answer.toLowerCase().contains(q) ||
              i.category.toLowerCase().contains(q),
        )
        .toList(growable: false);
  }
}
