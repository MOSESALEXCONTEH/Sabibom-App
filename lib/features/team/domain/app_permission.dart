/// Stable permission codes used across UI, Firestore rules, and Vercel.
enum AppPermission {
  // Sales
  createSale('create_sale'),
  viewOwnSales('view_own_sales'),
  viewAllSales('view_all_sales'),
  viewSaleDetails('view_sale_details'),
  shareReceipt('share_receipt'),
  printReceipt('print_receipt'),
  applyDiscount('apply_discount'),
  overridePrice('override_price'),
  voidSale('void_sale'),
  refundSale('refund_sale'),

  // Products and inventory
  viewProducts('view_products'),
  manageProducts('manage_products'),
  archiveProduct('archive_product'),
  adjustStock('adjust_stock'),
  viewInventoryMovements('view_inventory_movements'),
  viewCostPrice('view_cost_price'),
  manageCategories('manage_categories'),
  manageUnits('manage_units'),
  viewProductExpiry('view_product_expiry'),
  manageProductExpiry('manage_product_expiry'),
  disposeExpiredStock('dispose_expired_stock'),
  viewProductProfit('view_product_profit'),
  viewProductPotentialProfit('view_product_potential_profit'),
  exportExpiryReport('export_expiry_report'),
  exportProductProfitReport('export_product_profit_report'),

  // Customers
  viewCustomers('view_customers'),
  manageCustomers('manage_customers'),
  viewCustomerBalance('view_customer_balance'),
  recordCustomerPayment('record_customer_payment'),
  adjustCustomerBalance('adjust_customer_balance'),
  archiveCustomer('archive_customer'),

  // Expenses
  viewExpenses('view_expenses'),
  createExpense('create_expense'),
  editExpense('edit_expense'),
  voidExpense('void_expense'),
  manageExpenseCategories('manage_expense_categories'),

  // Suppliers and purchases
  viewSuppliers('view_suppliers'),
  manageSuppliers('manage_suppliers'),
  createPurchase('create_purchase'),
  viewPurchases('view_purchases'),
  recordSupplierPayment('record_supplier_payment'),
  createPurchaseReturn('create_purchase_return'),
  viewSupplierBalance('view_supplier_balance'),
  viewPurchaseCosts('view_purchase_costs'),

  // Reports
  viewSalesReports('view_sales_reports'),
  viewExpenseReports('view_expense_reports'),
  viewInventoryReports('view_inventory_reports'),
  viewCustomerReports('view_customer_reports'),
  viewSupplierReports('view_supplier_reports'),
  viewProfit('view_profit'),
  exportReports('export_reports'),

  // Receipts
  manageReceiptTemplates('manage_receipt_templates'),
  editBusinessBranding('edit_business_branding'),
  downloadReceiptPdf('download_receipt_pdf'),
  shareReceiptPdf('share_receipt_pdf'),

  // Sabi
  useSabi('use_sabi'),
  useSabiSales('use_sabi_sales'),
  useSabiExpenses('use_sabi_expenses'),
  useSabiPurchases('use_sabi_purchases'),
  askSabiBusinessQuestions('ask_sabi_business_questions'),
  askSabiProfitQuestions('ask_sabi_profit_questions'),

  // Business and team
  editBusinessSettings('edit_business_settings'),
  manageStaff('manage_staff'),
  manageRoles('manage_roles'),
  viewStaffActivity('view_staff_activity'),
  approveSensitiveActions('approve_sensitive_actions'),
  viewBranch('view_branch'),
  manageBranches('manage_branches'),
  switchBranch('switch_branch'),
  viewAllBranches('view_all_branches'),
  viewCombinedReports('view_combined_reports'),
  assignStaffToBranches('assign_staff_to_branches'),
  manageBranchOperations('manage_branch_operations'),

  // Notifications
  viewNotifications('view_notifications'),
  manageNotificationPreferences('manage_notification_preferences'),
  viewLowStockAlerts('view_low_stock_alerts'),
  viewCustomerDebtAlerts('view_customer_debt_alerts'),
  viewSupplierPaymentAlerts('view_supplier_payment_alerts'),
  viewApprovalNotifications('view_approval_notifications'),
  viewEndOfDayAlerts('view_end_of_day_alerts'),
  viewDailySummary('view_daily_summary'),
  viewWeeklyReport('view_weekly_report'),
  receivePushNotifications('receive_push_notifications'),
  sendCustomerReminderDraft('send_customer_reminder_draft'),
  viewStaffNotifications('view_staff_notifications');

  const AppPermission(this.code);

  final String code;

  static AppPermission? tryParse(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final needle = raw.trim().toLowerCase();
    final legacy = switch (needle) {
      'view_branches' => AppPermission.viewBranch,
      'switch_branches' => AppPermission.switchBranch,
      'view_all_branch_reports' => AppPermission.viewCombinedReports,
      'manage_branch_staff' => AppPermission.assignStaffToBranches,
      _ => null,
    };
    if (legacy != null) return legacy;
    for (final p in AppPermission.values) {
      if (p.code == needle || p.name.toLowerCase() == needle) return p;
    }
    return null;
  }

  static Set<AppPermission> parseMany(Iterable<Object?> raw) {
    final out = <AppPermission>{};
    for (final item in raw) {
      final parsed = tryParse('$item');
      if (parsed != null) out.add(parsed);
    }
    return out;
  }
}

enum PermissionGroup {
  sales,
  products,
  customers,
  expenses,
  suppliers,
  reports,
  receipts,
  sabi,
  business,
  notifications;

  String get title => switch (this) {
    PermissionGroup.sales => 'Sales',
    PermissionGroup.products => 'Products & inventory',
    PermissionGroup.customers => 'Customers',
    PermissionGroup.expenses => 'Expenses',
    PermissionGroup.suppliers => 'Suppliers & purchases',
    PermissionGroup.reports => 'Reports',
    PermissionGroup.receipts => 'Receipts',
    PermissionGroup.sabi => 'Sabi',
    PermissionGroup.business => 'Business & team',
    PermissionGroup.notifications => 'Notifications',
  };
}

class PermissionDefinition {
  const PermissionDefinition({
    required this.code,
    required this.title,
    required this.description,
    required this.group,
    this.sensitive = false,
    this.ownerOnly = false,
  });

  final AppPermission code;
  final String title;
  final String description;
  final PermissionGroup group;
  final bool sensitive;
  final bool ownerOnly;
}

/// Single source of truth for permission labels and metadata.
abstract final class PermissionRegistry {
  static const List<PermissionDefinition> all = <PermissionDefinition>[
    // Sales
    PermissionDefinition(
      code: AppPermission.createSale,
      title: 'Create sales',
      description: 'Create and complete sales.',
      group: PermissionGroup.sales,
    ),
    PermissionDefinition(
      code: AppPermission.viewOwnSales,
      title: 'View own sales',
      description: 'View sales created by this user.',
      group: PermissionGroup.sales,
    ),
    PermissionDefinition(
      code: AppPermission.viewAllSales,
      title: 'View all sales',
      description: 'View sales created by any staff member.',
      group: PermissionGroup.sales,
    ),
    PermissionDefinition(
      code: AppPermission.viewSaleDetails,
      title: 'View sale details',
      description: 'Open sale detail screens.',
      group: PermissionGroup.sales,
    ),
    PermissionDefinition(
      code: AppPermission.shareReceipt,
      title: 'Share receipts',
      description: 'Share sale receipts.',
      group: PermissionGroup.sales,
    ),
    PermissionDefinition(
      code: AppPermission.printReceipt,
      title: 'Print receipts',
      description: 'Print sale receipts.',
      group: PermissionGroup.sales,
    ),
    PermissionDefinition(
      code: AppPermission.applyDiscount,
      title: 'Apply discounts',
      description: 'Apply discounts on sales.',
      group: PermissionGroup.sales,
      sensitive: true,
    ),
    PermissionDefinition(
      code: AppPermission.overridePrice,
      title: 'Override prices',
      description: 'Change item prices during a sale.',
      group: PermissionGroup.sales,
      sensitive: true,
    ),
    PermissionDefinition(
      code: AppPermission.voidSale,
      title: 'Void sales',
      description: 'Void completed sales.',
      group: PermissionGroup.sales,
      sensitive: true,
    ),
    PermissionDefinition(
      code: AppPermission.refundSale,
      title: 'Refund sales',
      description: 'Process refunds for sales.',
      group: PermissionGroup.sales,
      sensitive: true,
    ),

    // Products
    PermissionDefinition(
      code: AppPermission.viewProducts,
      title: 'View products',
      description: 'Browse the product catalog.',
      group: PermissionGroup.products,
    ),
    PermissionDefinition(
      code: AppPermission.manageProducts,
      title: 'Manage products',
      description: 'Create and edit products.',
      group: PermissionGroup.products,
    ),
    PermissionDefinition(
      code: AppPermission.archiveProduct,
      title: 'Archive products',
      description: 'Archive products from the catalog.',
      group: PermissionGroup.products,
    ),
    PermissionDefinition(
      code: AppPermission.adjustStock,
      title: 'Adjust stock',
      description: 'Increase or decrease inventory quantities.',
      group: PermissionGroup.products,
      sensitive: true,
    ),
    PermissionDefinition(
      code: AppPermission.viewInventoryMovements,
      title: 'View inventory movements',
      description: 'See stock movement history.',
      group: PermissionGroup.products,
    ),
    PermissionDefinition(
      code: AppPermission.viewCostPrice,
      title: 'View cost price',
      description: 'See product cost prices.',
      group: PermissionGroup.products,
      sensitive: true,
    ),
    PermissionDefinition(
      code: AppPermission.manageCategories,
      title: 'Manage categories',
      description: 'Create and edit product categories.',
      group: PermissionGroup.products,
    ),
    PermissionDefinition(
      code: AppPermission.manageUnits,
      title: 'Manage units',
      description: 'Create and edit product units.',
      group: PermissionGroup.products,
    ),
    PermissionDefinition(
      code: AppPermission.viewProductExpiry,
      title: 'View product expiry',
      description: 'See nearest expiry dates and batch status.',
      group: PermissionGroup.products,
    ),
    PermissionDefinition(
      code: AppPermission.manageProductExpiry,
      title: 'Manage product expiry',
      description: 'Update batch expiry dates and expiry settings.',
      group: PermissionGroup.products,
      sensitive: true,
    ),
    PermissionDefinition(
      code: AppPermission.disposeExpiredStock,
      title: 'Dispose expired stock',
      description: 'Write off expired inventory with an audit trail.',
      group: PermissionGroup.products,
      sensitive: true,
    ),
    PermissionDefinition(
      code: AppPermission.viewProductProfit,
      title: 'View product profit',
      description: 'See realized and projected product profit.',
      group: PermissionGroup.products,
      sensitive: true,
    ),
    PermissionDefinition(
      code: AppPermission.viewProductPotentialProfit,
      title: 'View potential profit',
      description: 'See estimated profit remaining in current stock.',
      group: PermissionGroup.products,
      sensitive: true,
    ),
    PermissionDefinition(
      code: AppPermission.exportExpiryReport,
      title: 'Export expiry report',
      description: 'Export product expiry reports.',
      group: PermissionGroup.reports,
    ),
    PermissionDefinition(
      code: AppPermission.exportProductProfitReport,
      title: 'Export product profit report',
      description: 'Export product profit reports.',
      group: PermissionGroup.reports,
      sensitive: true,
    ),

    // Customers
    PermissionDefinition(
      code: AppPermission.viewCustomers,
      title: 'View customers',
      description: 'Browse the customer list.',
      group: PermissionGroup.customers,
    ),
    PermissionDefinition(
      code: AppPermission.manageCustomers,
      title: 'Manage customers',
      description: 'Create and edit customers.',
      group: PermissionGroup.customers,
    ),
    PermissionDefinition(
      code: AppPermission.viewCustomerBalance,
      title: 'View customer balances',
      description: 'See outstanding customer balances.',
      group: PermissionGroup.customers,
      sensitive: true,
    ),
    PermissionDefinition(
      code: AppPermission.recordCustomerPayment,
      title: 'Record customer payments',
      description: 'Record payments against customer balances.',
      group: PermissionGroup.customers,
    ),
    PermissionDefinition(
      code: AppPermission.adjustCustomerBalance,
      title: 'Adjust customer balances',
      description: 'Manually adjust customer balances.',
      group: PermissionGroup.customers,
      sensitive: true,
    ),
    PermissionDefinition(
      code: AppPermission.archiveCustomer,
      title: 'Archive customers',
      description: 'Archive customers.',
      group: PermissionGroup.customers,
    ),

    // Expenses
    PermissionDefinition(
      code: AppPermission.viewExpenses,
      title: 'View expenses',
      description: 'Browse expense records.',
      group: PermissionGroup.expenses,
    ),
    PermissionDefinition(
      code: AppPermission.createExpense,
      title: 'Create expenses',
      description: 'Record new expenses.',
      group: PermissionGroup.expenses,
    ),
    PermissionDefinition(
      code: AppPermission.editExpense,
      title: 'Edit expenses',
      description: 'Edit existing expenses.',
      group: PermissionGroup.expenses,
    ),
    PermissionDefinition(
      code: AppPermission.voidExpense,
      title: 'Void expenses',
      description: 'Void expense records.',
      group: PermissionGroup.expenses,
      sensitive: true,
    ),
    PermissionDefinition(
      code: AppPermission.manageExpenseCategories,
      title: 'Manage expense categories',
      description: 'Create and edit expense categories.',
      group: PermissionGroup.expenses,
    ),

    // Suppliers
    PermissionDefinition(
      code: AppPermission.viewSuppliers,
      title: 'View suppliers',
      description: 'Browse suppliers.',
      group: PermissionGroup.suppliers,
    ),
    PermissionDefinition(
      code: AppPermission.manageSuppliers,
      title: 'Manage suppliers',
      description: 'Create and edit suppliers.',
      group: PermissionGroup.suppliers,
    ),
    PermissionDefinition(
      code: AppPermission.createPurchase,
      title: 'Create purchases',
      description: 'Record supplier purchases.',
      group: PermissionGroup.suppliers,
    ),
    PermissionDefinition(
      code: AppPermission.viewPurchases,
      title: 'View purchases',
      description: 'Browse purchase records.',
      group: PermissionGroup.suppliers,
    ),
    PermissionDefinition(
      code: AppPermission.recordSupplierPayment,
      title: 'Record supplier payments',
      description: 'Record payments to suppliers.',
      group: PermissionGroup.suppliers,
    ),
    PermissionDefinition(
      code: AppPermission.createPurchaseReturn,
      title: 'Create purchase returns',
      description: 'Return purchased stock to suppliers.',
      group: PermissionGroup.suppliers,
      sensitive: true,
    ),
    PermissionDefinition(
      code: AppPermission.viewSupplierBalance,
      title: 'View supplier balances',
      description: 'See outstanding supplier balances.',
      group: PermissionGroup.suppliers,
      sensitive: true,
    ),
    PermissionDefinition(
      code: AppPermission.viewPurchaseCosts,
      title: 'View purchase costs',
      description: 'See purchase cost details.',
      group: PermissionGroup.suppliers,
      sensitive: true,
    ),

    // Reports
    PermissionDefinition(
      code: AppPermission.viewSalesReports,
      title: 'View sales reports',
      description: 'Open sales reports.',
      group: PermissionGroup.reports,
    ),
    PermissionDefinition(
      code: AppPermission.viewExpenseReports,
      title: 'View expense reports',
      description: 'Open expense reports.',
      group: PermissionGroup.reports,
    ),
    PermissionDefinition(
      code: AppPermission.viewInventoryReports,
      title: 'View inventory reports',
      description: 'Open inventory reports.',
      group: PermissionGroup.reports,
    ),
    PermissionDefinition(
      code: AppPermission.viewCustomerReports,
      title: 'View customer reports',
      description: 'Open customer balance reports.',
      group: PermissionGroup.reports,
    ),
    PermissionDefinition(
      code: AppPermission.viewSupplierReports,
      title: 'View supplier reports',
      description: 'Open supplier balance reports.',
      group: PermissionGroup.reports,
    ),
    PermissionDefinition(
      code: AppPermission.viewProfit,
      title: 'View profit',
      description: 'See profit and loss figures.',
      group: PermissionGroup.reports,
      sensitive: true,
    ),
    PermissionDefinition(
      code: AppPermission.exportReports,
      title: 'Export reports',
      description: 'Export report data.',
      group: PermissionGroup.reports,
    ),

    // Receipts
    PermissionDefinition(
      code: AppPermission.manageReceiptTemplates,
      title: 'Manage receipt templates',
      description: 'Edit receipt templates.',
      group: PermissionGroup.receipts,
    ),
    PermissionDefinition(
      code: AppPermission.editBusinessBranding,
      title: 'Edit business branding',
      description: 'Change logo and branding on receipts.',
      group: PermissionGroup.receipts,
    ),
    PermissionDefinition(
      code: AppPermission.downloadReceiptPdf,
      title: 'Download receipt PDF',
      description: 'Download receipt PDFs.',
      group: PermissionGroup.receipts,
    ),
    PermissionDefinition(
      code: AppPermission.shareReceiptPdf,
      title: 'Share receipt PDF',
      description: 'Share receipt PDFs.',
      group: PermissionGroup.receipts,
    ),

    // Sabi
    PermissionDefinition(
      code: AppPermission.useSabi,
      title: 'Use Sabi',
      description: 'Open and use the Sabi assistant.',
      group: PermissionGroup.sabi,
    ),
    PermissionDefinition(
      code: AppPermission.useSabiSales,
      title: 'Sabi sales drafts',
      description: 'Create sale drafts with Sabi.',
      group: PermissionGroup.sabi,
    ),
    PermissionDefinition(
      code: AppPermission.useSabiExpenses,
      title: 'Sabi expense drafts',
      description: 'Create expense drafts with Sabi.',
      group: PermissionGroup.sabi,
    ),
    PermissionDefinition(
      code: AppPermission.useSabiPurchases,
      title: 'Sabi purchase drafts',
      description: 'Create purchase drafts with Sabi.',
      group: PermissionGroup.sabi,
    ),
    PermissionDefinition(
      code: AppPermission.askSabiBusinessQuestions,
      title: 'Ask Sabi business questions',
      description: 'Ask Sabi about business data.',
      group: PermissionGroup.sabi,
    ),
    PermissionDefinition(
      code: AppPermission.askSabiProfitQuestions,
      title: 'Ask Sabi profit questions',
      description: 'Ask Sabi about profit and margins.',
      group: PermissionGroup.sabi,
      sensitive: true,
    ),

    // Business
    PermissionDefinition(
      code: AppPermission.editBusinessSettings,
      title: 'Edit business settings',
      description: 'Change business profile and settings.',
      group: PermissionGroup.business,
    ),
    PermissionDefinition(
      code: AppPermission.manageStaff,
      title: 'Manage staff',
      description: 'Invite, disable, and remove team members.',
      group: PermissionGroup.business,
      sensitive: true,
    ),
    PermissionDefinition(
      code: AppPermission.manageRoles,
      title: 'Manage roles',
      description: 'Create and edit custom roles.',
      group: PermissionGroup.business,
      sensitive: true,
    ),
    PermissionDefinition(
      code: AppPermission.viewStaffActivity,
      title: 'View staff activity',
      description: 'See the staff activity log.',
      group: PermissionGroup.business,
    ),
    PermissionDefinition(
      code: AppPermission.approveSensitiveActions,
      title: 'Approve sensitive actions',
      description: 'Approve or reject approval requests.',
      group: PermissionGroup.business,
      sensitive: true,
    ),
    PermissionDefinition(
      code: AppPermission.viewBranch,
      title: 'View assigned branches',
      description: 'View assigned branch details and records.',
      group: PermissionGroup.business,
    ),
    PermissionDefinition(
      code: AppPermission.manageBranches,
      title: 'Manage branches',
      description: 'Create and edit business branches.',
      group: PermissionGroup.business,
      sensitive: true,
    ),
    PermissionDefinition(
      code: AppPermission.switchBranch,
      title: 'Switch branches',
      description: 'Change the active branch context.',
      group: PermissionGroup.business,
    ),
    PermissionDefinition(
      code: AppPermission.viewAllBranches,
      title: 'View all branches',
      description: 'View the full branch list without operational access.',
      group: PermissionGroup.business,
      sensitive: true,
    ),
    PermissionDefinition(
      code: AppPermission.viewCombinedReports,
      title: 'View combined reports',
      description: 'See consolidated reporting across branches.',
      group: PermissionGroup.business,
      sensitive: true,
    ),
    PermissionDefinition(
      code: AppPermission.assignStaffToBranches,
      title: 'Assign staff to branches',
      description: 'Assign staff to branches.',
      group: PermissionGroup.business,
      sensitive: true,
    ),
    PermissionDefinition(
      code: AppPermission.manageBranchOperations,
      title: 'Manage branch operations',
      description: 'Perform allowed operations inside assigned branches.',
      group: PermissionGroup.business,
      sensitive: true,
    ),
    // Notifications
    PermissionDefinition(
      code: AppPermission.viewNotifications,
      title: 'View notifications',
      description: 'Open the notification centre.',
      group: PermissionGroup.notifications,
    ),
    PermissionDefinition(
      code: AppPermission.manageNotificationPreferences,
      title: 'Manage notification preferences',
      description: 'Change notification and reminder settings.',
      group: PermissionGroup.notifications,
    ),
    PermissionDefinition(
      code: AppPermission.viewLowStockAlerts,
      title: 'View low-stock alerts',
      description: 'Receive inventory low and out-of-stock alerts.',
      group: PermissionGroup.notifications,
    ),
    PermissionDefinition(
      code: AppPermission.viewCustomerDebtAlerts,
      title: 'View customer debt alerts',
      description: 'See customer credit and overdue balance alerts.',
      group: PermissionGroup.notifications,
    ),
    PermissionDefinition(
      code: AppPermission.viewSupplierPaymentAlerts,
      title: 'View supplier payment alerts',
      description: 'See supplier payment and balance alerts.',
      group: PermissionGroup.notifications,
    ),
    PermissionDefinition(
      code: AppPermission.viewApprovalNotifications,
      title: 'View approval notifications',
      description: 'Receive approval request and decision alerts.',
      group: PermissionGroup.notifications,
    ),
    PermissionDefinition(
      code: AppPermission.viewEndOfDayAlerts,
      title: 'View End-of-Day alerts',
      description: 'Receive End-of-Day reminder and cash difference alerts.',
      group: PermissionGroup.notifications,
    ),
    PermissionDefinition(
      code: AppPermission.viewDailySummary,
      title: 'View daily summary',
      description: 'Open verified daily business summaries.',
      group: PermissionGroup.notifications,
    ),
    PermissionDefinition(
      code: AppPermission.viewWeeklyReport,
      title: 'View weekly report',
      description: 'Open verified weekly business reports.',
      group: PermissionGroup.notifications,
    ),
    PermissionDefinition(
      code: AppPermission.receivePushNotifications,
      title: 'Receive push notifications',
      description: 'Allow lock-screen and background push delivery.',
      group: PermissionGroup.notifications,
    ),
    PermissionDefinition(
      code: AppPermission.sendCustomerReminderDraft,
      title: 'Prepare customer reminder drafts',
      description: 'Create editable reminder messages for customers.',
      group: PermissionGroup.notifications,
    ),
    PermissionDefinition(
      code: AppPermission.viewStaffNotifications,
      title: 'View staff notifications',
      description: 'Receive invitation, role, and membership alerts.',
      group: PermissionGroup.notifications,
    ),
  ];

  static PermissionDefinition? byCode(AppPermission permission) {
    for (final d in all) {
      if (d.code == permission) return d;
    }
    return null;
  }

  static List<PermissionDefinition> byGroup(PermissionGroup group) {
    return all.where((d) => d.group == group).toList(growable: false);
  }

  static Set<String> codesOf(Iterable<AppPermission> permissions) {
    return permissions.map((p) => p.code).toSet();
  }
}
