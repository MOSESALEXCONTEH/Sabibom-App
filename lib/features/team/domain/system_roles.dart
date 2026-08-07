import 'app_permission.dart';

/// Built-in role document IDs (also used as legacy `role` string values).
abstract final class SystemRoleIds {
  static const owner = 'owner';
  static const admin = 'admin';
  static const manager = 'manager';
  static const cashier = 'cashier';
  static const staff = 'staff';
  static const stockKeeper = 'stock_keeper';
  static const accountant = 'accountant';
  static const custom = 'custom';

  static const List<String> all = <String>[
    owner,
    admin,
    manager,
    cashier,
    staff,
    stockKeeper,
    accountant,
  ];

  static bool isSystem(String roleId) => all.contains(roleId);
}

class RoleDefinition {
  const RoleDefinition({
    required this.id,
    required this.businessId,
    required this.name,
    required this.description,
    required this.permissions,
    required this.isSystemRole,
    required this.isEditable,
    this.isActive = true,
    this.createdBy,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String businessId;
  final String name;
  final String description;
  final Set<AppPermission> permissions;
  final bool isSystemRole;
  final bool isEditable;
  final bool isActive;
  final String? createdBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'businessId': businessId,
      'name': name,
      'description': description,
      'permissions': permissions.map((p) => p.code).toList(),
      'isSystemRole': isSystemRole,
      'isEditable': isEditable,
      'isActive': isActive,
      'createdBy': createdBy,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }

  factory RoleDefinition.fromMap(
    String id,
    String businessId,
    Map<String, dynamic> data,
  ) {
    return RoleDefinition(
      id: id,
      businessId: businessId,
      name: (data['name'] as String?)?.trim() ?? id,
      description: (data['description'] as String?)?.trim() ?? '',
      permissions: AppPermission.parseMany(data['permissions'] as List? ?? []),
      isSystemRole: data['isSystemRole'] == true,
      isEditable: data['isEditable'] != false && data['isSystemRole'] != true
          ? true
          : data['isEditable'] == true,
      isActive: data['isActive'] != false,
      createdBy: data['createdBy'] as String?,
    );
  }

  RoleDefinition copyWith({
    String? name,
    String? description,
    Set<AppPermission>? permissions,
    bool? isActive,
  }) {
    return RoleDefinition(
      id: id,
      businessId: businessId,
      name: name ?? this.name,
      description: description ?? this.description,
      permissions: permissions ?? this.permissions,
      isSystemRole: isSystemRole,
      isEditable: isEditable,
      isActive: isActive ?? this.isActive,
      createdBy: createdBy,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}

/// Default built-in roles and their permission sets.
abstract final class SystemRoles {
  static String labelFor(String roleId) {
    return switch (roleId) {
      SystemRoleIds.owner => 'Owner',
      SystemRoleIds.admin => 'Business Admin',
      SystemRoleIds.manager => 'Manager',
      SystemRoleIds.cashier => 'Cashier',
      SystemRoleIds.staff => 'Staff',
      SystemRoleIds.stockKeeper => 'Stock Keeper',
      SystemRoleIds.accountant => 'Accountant',
      SystemRoleIds.custom => 'Custom',
      _ => roleId.replaceAll('_', ' '),
    };
  }

  static String descriptionFor(String roleId) {
    return switch (roleId) {
      SystemRoleIds.owner => 'Full access to the business. Cannot be removed.',
      SystemRoleIds.admin =>
        'Assigned branch operations with separately granted administration.',
      SystemRoleIds.manager =>
        'Daily operations, reports, staff supervision, and approvals.',
      SystemRoleIds.cashier =>
        'Create sales, manage customers, and share receipts.',
      SystemRoleIds.staff => 'Assigned branch access with limited operations.',
      SystemRoleIds.stockKeeper => 'Products, stock, purchases, and suppliers.',
      SystemRoleIds.accountant =>
        'Expenses, purchases, payments, reports, and profit.',
      _ => 'Custom role with selected permissions.',
    };
  }

  static Set<AppPermission> defaultPermissionsFor(String roleId) {
    return switch (roleId) {
      SystemRoleIds.owner => AppPermission.values.toSet(),
      SystemRoleIds.admin => _manager,
      SystemRoleIds.manager => _manager,
      SystemRoleIds.cashier => _cashier,
      SystemRoleIds.staff => _staff,
      SystemRoleIds.stockKeeper => _stockKeeper,
      SystemRoleIds.accountant => _accountant,
      _ => const <AppPermission>{},
    };
  }

  static List<RoleDefinition> buildDefaults(String businessId) {
    return SystemRoleIds.all
        .map(
          (id) => RoleDefinition(
            id: id,
            businessId: businessId,
            name: labelFor(id),
            description: descriptionFor(id),
            permissions: defaultPermissionsFor(id),
            isSystemRole: true,
            isEditable: false,
            isActive: true,
          ),
        )
        .toList(growable: false);
  }

  static const Set<AppPermission> _manager = {
    // Sales
    AppPermission.createSale,
    AppPermission.viewOwnSales,
    AppPermission.viewAllSales,
    AppPermission.viewSaleDetails,
    AppPermission.shareReceipt,
    AppPermission.printReceipt,
    AppPermission.applyDiscount,
    AppPermission.overridePrice,
    AppPermission.voidSale,
    AppPermission.refundSale,
    // Products
    AppPermission.viewProducts,
    AppPermission.manageProducts,
    AppPermission.archiveProduct,
    AppPermission.adjustStock,
    AppPermission.viewInventoryMovements,
    AppPermission.viewCostPrice,
    AppPermission.manageCategories,
    AppPermission.manageUnits,
    AppPermission.viewProductExpiry,
    AppPermission.manageProductExpiry,
    AppPermission.disposeExpiredStock,
    AppPermission.viewProductProfit,
    AppPermission.viewProductPotentialProfit,
    AppPermission.exportExpiryReport,
    AppPermission.exportProductProfitReport,
    // Customers
    AppPermission.viewCustomers,
    AppPermission.manageCustomers,
    AppPermission.viewCustomerBalance,
    AppPermission.recordCustomerPayment,
    AppPermission.adjustCustomerBalance,
    AppPermission.archiveCustomer,
    // Expenses
    AppPermission.viewExpenses,
    AppPermission.createExpense,
    AppPermission.editExpense,
    AppPermission.voidExpense,
    AppPermission.manageExpenseCategories,
    // Suppliers
    AppPermission.viewSuppliers,
    AppPermission.manageSuppliers,
    AppPermission.createPurchase,
    AppPermission.viewPurchases,
    AppPermission.recordSupplierPayment,
    AppPermission.createPurchaseReturn,
    AppPermission.viewSupplierBalance,
    AppPermission.viewPurchaseCosts,
    // Reports
    AppPermission.viewSalesReports,
    AppPermission.viewExpenseReports,
    AppPermission.viewInventoryReports,
    AppPermission.viewCustomerReports,
    AppPermission.viewSupplierReports,
    AppPermission.viewProfit,
    AppPermission.exportReports,
    // Receipts
    AppPermission.manageReceiptTemplates,
    AppPermission.editBusinessBranding,
    AppPermission.downloadReceiptPdf,
    AppPermission.shareReceiptPdf,
    // Sabi
    AppPermission.useSabi,
    AppPermission.useSabiSales,
    AppPermission.useSabiExpenses,
    AppPermission.useSabiPurchases,
    AppPermission.askSabiBusinessQuestions,
    AppPermission.askSabiProfitQuestions,
    // Business
    AppPermission.editBusinessSettings,
    AppPermission.manageStaff,
    AppPermission.manageRoles,
    AppPermission.viewStaffActivity,
    AppPermission.approveSensitiveActions,
    AppPermission.viewBranch,
    AppPermission.switchBranch,
    AppPermission.manageBranchOperations,
    // Notifications
    AppPermission.viewNotifications,
    AppPermission.manageNotificationPreferences,
    AppPermission.viewLowStockAlerts,
    AppPermission.viewCustomerDebtAlerts,
    AppPermission.viewSupplierPaymentAlerts,
    AppPermission.viewApprovalNotifications,
    AppPermission.viewEndOfDayAlerts,
    AppPermission.viewDailySummary,
    AppPermission.viewWeeklyReport,
    AppPermission.receivePushNotifications,
    AppPermission.sendCustomerReminderDraft,
    AppPermission.viewStaffNotifications,
  };

  static const Set<AppPermission> _cashier = {
    AppPermission.createSale,
    AppPermission.viewOwnSales,
    AppPermission.viewSaleDetails,
    AppPermission.shareReceipt,
    AppPermission.printReceipt,
    AppPermission.applyDiscount,
    AppPermission.viewProducts,
    AppPermission.viewProductExpiry,
    AppPermission.viewCustomers,
    AppPermission.manageCustomers,
    AppPermission.recordCustomerPayment,
    AppPermission.downloadReceiptPdf,
    AppPermission.shareReceiptPdf,
    AppPermission.useSabi,
    AppPermission.useSabiSales,
    AppPermission.askSabiBusinessQuestions,
    AppPermission.viewBranch,
    AppPermission.manageBranchOperations,
    AppPermission.viewNotifications,
    AppPermission.viewLowStockAlerts,
    AppPermission.viewApprovalNotifications,
    AppPermission.viewEndOfDayAlerts,
    AppPermission.viewDailySummary,
    AppPermission.receivePushNotifications,
  };

  static const Set<AppPermission> _staff = {
    AppPermission.viewBranch,
    AppPermission.manageBranchOperations,
  };

  static const Set<AppPermission> _stockKeeper = {
    AppPermission.viewProducts,
    AppPermission.manageProducts,
    AppPermission.archiveProduct,
    AppPermission.adjustStock,
    AppPermission.viewInventoryMovements,
    AppPermission.viewCostPrice,
    AppPermission.manageCategories,
    AppPermission.manageUnits,
    AppPermission.viewProductExpiry,
    AppPermission.manageProductExpiry,
    AppPermission.disposeExpiredStock,
    AppPermission.exportExpiryReport,
    AppPermission.viewSuppliers,
    AppPermission.manageSuppliers,
    AppPermission.createPurchase,
    AppPermission.viewPurchases,
    AppPermission.recordSupplierPayment,
    AppPermission.createPurchaseReturn,
    AppPermission.viewSupplierBalance,
    AppPermission.viewPurchaseCosts,
    AppPermission.viewInventoryReports,
    AppPermission.viewSupplierReports,
    AppPermission.exportReports,
    AppPermission.useSabi,
    AppPermission.useSabiPurchases,
    AppPermission.askSabiBusinessQuestions,
    AppPermission.viewBranch,
    AppPermission.manageBranchOperations,
    AppPermission.viewNotifications,
    AppPermission.viewLowStockAlerts,
    AppPermission.receivePushNotifications,
  };

  static const Set<AppPermission> _accountant = {
    AppPermission.viewOwnSales,
    AppPermission.viewAllSales,
    AppPermission.viewSaleDetails,
    AppPermission.viewProducts,
    AppPermission.viewCostPrice,
    AppPermission.viewCustomers,
    AppPermission.viewCustomerBalance,
    AppPermission.recordCustomerPayment,
    AppPermission.viewExpenses,
    AppPermission.createExpense,
    AppPermission.editExpense,
    AppPermission.voidExpense,
    AppPermission.manageExpenseCategories,
    AppPermission.viewSuppliers,
    AppPermission.viewPurchases,
    AppPermission.recordSupplierPayment,
    AppPermission.viewSupplierBalance,
    AppPermission.viewPurchaseCosts,
    AppPermission.viewSalesReports,
    AppPermission.viewExpenseReports,
    AppPermission.viewInventoryReports,
    AppPermission.viewCustomerReports,
    AppPermission.viewSupplierReports,
    AppPermission.viewProfit,
    AppPermission.viewProductProfit,
    AppPermission.viewProductPotentialProfit,
    AppPermission.exportProductProfitReport,
    AppPermission.viewProductExpiry,
    AppPermission.exportExpiryReport,
    AppPermission.exportReports,
    AppPermission.useSabi,
    AppPermission.useSabiExpenses,
    AppPermission.askSabiBusinessQuestions,
    AppPermission.askSabiProfitQuestions,
    AppPermission.viewBranch,
    AppPermission.manageBranchOperations,
    AppPermission.viewNotifications,
    AppPermission.viewCustomerDebtAlerts,
    AppPermission.viewSupplierPaymentAlerts,
    AppPermission.viewDailySummary,
    AppPermission.viewWeeklyReport,
    AppPermission.receivePushNotifications,
    AppPermission.sendCustomerReminderDraft,
  };
}
