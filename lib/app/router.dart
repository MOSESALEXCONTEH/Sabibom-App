import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'app_shell.dart';
import '../features/auth/presentation/auth_screens.dart';
import '../features/account_deletion/presentation/deletion_requests_screen.dart';
import '../features/business_profile/presentation/business_profile_screen.dart';
import '../features/business_setup/presentation/business_setup_choice_screen.dart';
import '../features/business_setup/presentation/business_setup_screen.dart';
import '../features/customers/presentation/customer_details_screen.dart';
import '../features/customers/presentation/customer_form_screen.dart';
import '../features/customers/presentation/customer_message_campaign_screen.dart';
import '../features/customers/presentation/customer_payment_screen.dart';
import '../features/customers/presentation/customers_screen.dart';
import '../features/dashboard/presentation/dashboard_screen.dart';
import '../features/billing/presentation/billing_screen.dart';
import '../features/more/presentation/more_screen.dart';
import '../features/backup/presentation/backup_screen.dart';
import '../features/end_of_day/presentation/end_of_day_screen.dart';
import '../features/notifications/application/business_summary_service.dart';
import '../features/notifications/presentation/notifications_screen.dart';
import '../features/notifications/presentation/attention_section.dart';
import '../features/notifications/presentation/summary_screens.dart';
import '../features/onboarding/presentation/onboarding_screen.dart';
import '../features/branches/presentation/business_branches_screen.dart';
import '../features/products/presentation/product_details_screen.dart';
import '../features/products/presentation/product_form_screen.dart';
import '../features/products/presentation/products_screen.dart';
import '../features/products/presentation/stock_adjustment_screen.dart';
import '../features/settings/presentation/categories_settings_screen.dart';
import '../features/help/data/feedback_repository.dart';
import '../features/help/presentation/help_screens.dart';
import '../features/settings/presentation/info_pages.dart';
import '../features/settings/presentation/release_readiness_screen.dart';
import '../features/settings/presentation/inventory_settings_screen.dart';
import '../features/settings/presentation/notifications_settings_screen.dart';
import '../features/settings/presentation/printer_settings_screen.dart';
import '../features/settings/presentation/profile_settings_screen.dart';
import '../features/settings/presentation/security_settings_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/settings/presentation/tax_currency_screen.dart';
import '../features/settings/presentation/units_settings_screen.dart';
import '../features/expenses/presentation/expenses_screens.dart';
import '../features/suppliers/presentation/suppliers_screens.dart';
import '../features/purchases/presentation/purchases_screens.dart';
import '../features/reports/presentation/product_intelligence_report_screens.dart';
import '../features/reports/presentation/reports_screens.dart';
import '../features/shell/presentation/module_placeholder_screen.dart';
import '../features/receipts/presentation/receipt_designer_screen.dart';
import '../features/sabi/presentation/sabi_sale_draft_screen.dart';
import '../features/sales/data/sales_repository.dart';
import '../features/sales/presentation/sale_details_screen.dart';
import '../features/sales/presentation/sales_screens.dart';
import '../features/splash/splash_screen.dart';
import '../features/team/presentation/accept_invitation_screen.dart';
import '../features/team/presentation/approvals_screens.dart';
import '../features/team/presentation/invite_staff_screen.dart';
import '../features/team/presentation/roles_activity_screens.dart';
import '../features/team/presentation/staff_details_screen.dart';
import '../features/team/presentation/team_screen.dart';
import '../features/team/presentation/team_widgets.dart';

/// Stable navigator keys — declared once, never recreated in build().
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'root',
);
final GlobalKey<NavigatorState> homeNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'home',
);
final GlobalKey<NavigatorState> salesNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'sales',
);
final GlobalKey<NavigatorState> productsNavigatorKey =
    GlobalKey<NavigatorState>(debugLabel: 'products');
final GlobalKey<NavigatorState> customersNavigatorKey =
    GlobalKey<NavigatorState>(debugLabel: 'customers');
final GlobalKey<NavigatorState> moreNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'more',
);

abstract final class AppRoutes {
  static const splash = '/';
  static const onboarding = '/onboarding';
  static const login = '/login';
  static const register = '/register';
  static const businessSetupChoice = '/business-setup-choice';
  static const businessSetup = '/business-setup';
  static const businessProfile = '/business-profile';
  static const home = '/home';
  static const dashboard = home;
  static const sales = '/sales';
  static const newSale = '/sales/new';
  static const checkout = '/sales/checkout';
  static const products = '/products';
  static const customers = '/customers';
  static const more = '/more';
  static const settings = '/settings';
  static const settingsBusiness = '/settings/business';
  static const settingsReceipt = '/settings/receipt';
  static const settingsTax = '/settings/tax';
  static const settingsPrinter = '/settings/printer';
  static const settingsProfile = '/settings/profile';
  static const settingsTeam = '/settings/team';
  static const settingsBranches = '/settings/branches';
  static const team = '/team';
  static const teamInvite = '/team/invite';
  static const teamActivity = '/team/activity';
  static const teamRoles = '/team/roles';
  static const teamRoleNew = '/team/roles/new';
  static const invite = '/invite';
  static const approvals = '/approvals';
  static const approvalSettings = '/approvals/settings';
  static const myRole = '/my-role';
  static const settingsCategories = '/settings/categories';
  static const settingsUnits = '/settings/units';
  static const settingsInventory = '/settings/inventory';
  static const settingsSecurity = '/settings/security';
  static const settingsNotifications = '/settings/notifications';
  static const billing = '/settings/billing';
  static const privacy = '/privacy';
  static const terms = '/terms';
  static const expenses = '/expenses';
  static const newExpense = '/expenses/new';
  static const expenseCategories = '/expenses/categories';
  static const suppliers = '/suppliers';
  static const newSupplier = '/suppliers/new';
  static const purchases = '/purchases';
  static const newPurchase = '/purchases/new';
  static const sabiAssistant = '/sabi';
  static const sabiSaleDraft = '/sales/sabi-draft';
  static const notifications = '/notifications';
  static const attention = '/attention';
  static const activity = '/activity';
  static const reports = '/reports';
  static const dailySummary = '/reports/daily-summary';
  static const weeklyReport = '/reports/weekly';
  static const endOfDay = '/reports/end-of-day';
  static const backup = '/backup';
  static const help = '/help';
  static const helpFaq = '/help/faq';
  static const helpFeedback = '/help/feedback';
  static const helpContact = '/help/contact';
  static const helpReportProblem = '/help/report-problem';
  static const about = '/about';
  static const accessDenied = '/access-denied';
  static const releaseReadiness = '/settings/release-readiness';
  static const deletionRequests = '/settings/deletion-requests';

  static String saleDetails(String saleId) => '$sales/$saleId';
  static String saleReceipt(String saleId) => '$sales/$saleId/receipt';
  static String expenseDetails(String expenseId) => '$expenses/$expenseId';
  static String editExpense(String expenseId) => '$expenses/$expenseId/edit';
  static String supplierDetails(String supplierId) => '$suppliers/$supplierId';
  static String purchaseDetails(String purchaseId) => '$purchases/$purchaseId';
}

abstract final class AppRouteNames {
  static const home = 'home';
  static const sales = 'sales';
  static const newSale = 'newSale';
  static const checkout = 'checkout';
  static const saleSuccess = 'saleSuccess';
  static const saleDetails = 'saleDetails';
  static const saleReceipt = 'saleReceipt';
  static const products = 'products';
  static const newProduct = 'newProduct';
  static const productDetails = 'productDetails';
  static const editProduct = 'editProduct';
  static const adjustStock = 'adjustStock';
  static const customers = 'customers';
  static const customerMessageCampaign = 'customerMessageCampaign';
  static const newCustomer = 'newCustomer';
  static const customerDetails = 'customerDetails';
  static const editCustomer = 'editCustomer';
  static const customerPayment = 'customerPayment';
  static const more = 'more';
  static const settings = 'settings';
  static const settingsBusiness = 'settingsBusiness';
  static const settingsReceipt = 'settingsReceipt';
  static const receiptDesigner = 'receiptDesigner';
  static const settingsTax = 'settingsTax';
  static const settingsPrinter = 'settingsPrinter';
  static const settingsProfile = 'settingsProfile';
  static const settingsTeam = 'settingsTeam';
  static const settingsBranches = 'settingsBranches';
  static const team = 'team';
  static const teamInvite = 'teamInvite';
  static const teamActivity = 'teamActivity';
  static const teamRoles = 'teamRoles';
  static const teamRoleNew = 'teamRoleNew';
  static const teamRoleEdit = 'teamRoleEdit';
  static const teamMember = 'teamMember';
  static const teamMemberEditRole = 'teamMemberEditRole';
  static const teamMemberPermissions = 'teamMemberPermissions';
  static const invite = 'invite';
  static const inviteWithId = 'inviteWithId';
  static const approvals = 'approvals';
  static const approvalDetails = 'approvalDetails';
  static const approvalSettings = 'approvalSettings';
  static const myRole = 'myRole';
  static const settingsCategories = 'settingsCategories';
  static const settingsUnits = 'settingsUnits';
  static const settingsInventory = 'settingsInventory';
  static const settingsSecurity = 'settingsSecurity';
  static const settingsNotifications = 'settingsNotifications';
  static const notifications = 'notifications';
  static const billing = 'billing';
  static const privacy = 'privacy';
  static const terms = 'terms';
  static const sabiSaleDraft = 'sabiSaleDraft';
  static const expenses = 'expenses';
  static const newExpense = 'newExpense';
  static const expenseDetails = 'expenseDetails';
  static const editExpense = 'editExpense';
  static const expenseCategories = 'expenseCategories';
  static const suppliers = 'suppliers';
  static const newSupplier = 'newSupplier';
  static const supplierDetails = 'supplierDetails';
  static const editSupplier = 'editSupplier';
  static const supplierPayment = 'supplierPayment';
  static const purchases = 'purchases';
  static const newPurchase = 'newPurchase';
  static const purchaseDetails = 'purchaseDetails';
  static const purchaseReturn = 'purchaseReturn';
  static const reports = 'reports';
  static const reportProfitLoss = 'reportProfitLoss';
  static const reportProductProfit = 'reportProductProfit';
  static const reportProductExpiry = 'reportProductExpiry';
  static const reportInventory = 'reportInventory';
  static const reportCustomerBalances = 'reportCustomerBalances';
  static const reportSupplierBalances = 'reportSupplierBalances';
  static const dailySummary = 'dailySummary';
  static const weeklyReport = 'weeklyReport';
  static const endOfDay = 'endOfDay';
  static const backup = 'backup';
  static const help = 'help';
  static const helpFaq = 'helpFaq';
  static const helpFeedback = 'helpFeedback';
  static const helpContact = 'helpContact';
  static const helpReportProblem = 'helpReportProblem';
  static const about = 'about';
  static const releaseReadiness = 'releaseReadiness';
  static const deletionRequests = 'deletionRequests';
}

final GoRouter appRouter = GoRouter(
  navigatorKey: rootNavigatorKey,
  initialLocation: AppRoutes.splash,
  refreshListenable: _AuthRefreshNotifier.instance,
  redirect: (context, state) {
    final location = state.matchedLocation;
    const guestRoutes = <String>{
      AppRoutes.onboarding,
      AppRoutes.login,
      AppRoutes.register,
    };
    final session = _AuthRefreshNotifier.instance;
    if (!session.isResolved) {
      return location == AppRoutes.splash ? null : AppRoutes.splash;
    }
    if (session.user == null) {
      // Never park a signed-out user on the splash screen.
      if (location == AppRoutes.splash) {
        return AppRoutes.onboarding;
      }
      if (guestRoutes.contains(location)) {
        return null;
      }
      return AppRoutes.onboarding;
    }
    if (location == AppRoutes.splash || guestRoutes.contains(location)) {
      return AppRoutes.home;
    }
    return null;
  },
  routes: <RouteBase>[
    GoRoute(path: AppRoutes.splash, builder: (_, _) => const SplashScreen()),
    GoRoute(
      path: AppRoutes.onboarding,
      builder: (_, _) => const OnboardingScreen(),
    ),
    GoRoute(path: AppRoutes.login, builder: (_, _) => const LoginScreen()),
    GoRoute(
      path: AppRoutes.register,
      builder: (_, _) => const RegisterScreen(),
    ),
    GoRoute(
      path: AppRoutes.businessSetupChoice,
      builder: (_, _) => const BusinessSetupChoiceScreen(),
    ),
    GoRoute(
      path: AppRoutes.businessSetup,
      builder: (_, _) => const BusinessSetupScreen(),
    ),
    GoRoute(
      path: AppRoutes.businessProfile,
      builder: (_, _) => const BusinessProfileScreen(),
    ),
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          AuthenticatedAppShell(navigationShell: navigationShell),
      branches: <StatefulShellBranch>[
        StatefulShellBranch(
          navigatorKey: homeNavigatorKey,
          routes: <RouteBase>[
            GoRoute(
              path: AppRoutes.home,
              name: AppRouteNames.home,
              builder: (_, _) => const DashboardScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          navigatorKey: salesNavigatorKey,
          routes: <RouteBase>[
            GoRoute(
              path: AppRoutes.sales,
              name: AppRouteNames.sales,
              builder: (_, _) => const SalesScreen(),
              routes: <RouteBase>[
                GoRoute(
                  path: 'sabi-draft',
                  name: AppRouteNames.sabiSaleDraft,
                  builder: (_, state) => SabiSaleDraftScreen(
                    initialTranscript: state.uri.queryParameters['q'],
                    startWithVoice: state.uri.queryParameters['voice'] == '1',
                  ),
                ),
                GoRoute(
                  path: 'new',
                  name: AppRouteNames.newSale,
                  builder: (_, _) => const NewSaleScreen(),
                ),
                GoRoute(
                  path: 'checkout',
                  name: AppRouteNames.checkout,
                  builder: (_, _) => const CheckoutScreen(),
                ),
                GoRoute(
                  path: 'success/:saleId',
                  name: AppRouteNames.saleSuccess,
                  builder: (_, state) => SaleCompleteScreen(
                    saleId: state.pathParameters['saleId']!,
                    completed: state.extra as CompletedSale?,
                  ),
                ),
                GoRoute(
                  path: ':saleId',
                  name: AppRouteNames.saleDetails,
                  builder: (context, state) {
                    final saleId = state.pathParameters['saleId'];
                    if (saleId == null || saleId.trim().isEmpty) {
                      return const InvalidSaleScreen();
                    }
                    return SaleDetailsScreen(saleId: saleId);
                  },
                  routes: <RouteBase>[
                    GoRoute(
                      path: 'receipt',
                      name: AppRouteNames.saleReceipt,
                      builder: (_, state) {
                        final saleId = state.pathParameters['saleId'];
                        if (saleId == null || saleId.trim().isEmpty) {
                          return const InvalidSaleScreen();
                        }
                        return DigitalReceiptScreen(saleId: saleId);
                      },
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
        StatefulShellBranch(
          navigatorKey: productsNavigatorKey,
          routes: <RouteBase>[
            GoRoute(
              path: AppRoutes.products,
              name: AppRouteNames.products,
              builder: (_, _) => const ProductsScreen(),
              routes: <RouteBase>[
                GoRoute(
                  path: 'new',
                  name: AppRouteNames.newProduct,
                  builder: (_, _) => const AddProductScreen(),
                ),
                GoRoute(
                  path: ':productId',
                  name: AppRouteNames.productDetails,
                  builder: (_, state) {
                    final productId = state.pathParameters['productId'];
                    if (productId == null || productId.trim().isEmpty) {
                      return const Scaffold(
                        body: Center(child: Text('Product not found.')),
                      );
                    }
                    return ProductDetailsScreen(productId: productId);
                  },
                  routes: <RouteBase>[
                    GoRoute(
                      path: 'edit',
                      name: AppRouteNames.editProduct,
                      builder: (_, state) => EditProductScreen(
                        productId: state.pathParameters['productId']!,
                      ),
                    ),
                    GoRoute(
                      path: 'adjust-stock',
                      name: AppRouteNames.adjustStock,
                      builder: (_, state) => StockAdjustmentScreen(
                        productId: state.pathParameters['productId']!,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
        StatefulShellBranch(
          navigatorKey: customersNavigatorKey,
          routes: <RouteBase>[
            GoRoute(
              path: AppRoutes.customers,
              name: AppRouteNames.customers,
              builder: (_, _) => const CustomersScreen(),
              routes: <RouteBase>[
                GoRoute(
                  path: 'message',
                  name: AppRouteNames.customerMessageCampaign,
                  builder: (_, state) => CustomerMessageCampaignScreen(
                    preselectedCustomerId:
                        state.uri.queryParameters['customerId'],
                  ),
                ),
                GoRoute(
                  path: 'new',
                  name: AppRouteNames.newCustomer,
                  builder: (_, state) => AddCustomerScreen(
                    returnToCheckout:
                        state.uri.queryParameters['returnTo'] == 'checkout',
                  ),
                ),
                GoRoute(
                  path: ':customerId',
                  name: AppRouteNames.customerDetails,
                  builder: (_, state) {
                    final customerId = state.pathParameters['customerId'];
                    if (customerId == null || customerId.trim().isEmpty) {
                      return const Scaffold(
                        body: Center(child: Text('Customer not found.')),
                      );
                    }
                    return CustomerDetailsScreen(customerId: customerId);
                  },
                  routes: <RouteBase>[
                    GoRoute(
                      path: 'edit',
                      name: AppRouteNames.editCustomer,
                      builder: (_, state) => EditCustomerScreen(
                        customerId: state.pathParameters['customerId']!,
                      ),
                    ),
                    GoRoute(
                      path: 'payment',
                      name: AppRouteNames.customerPayment,
                      builder: (_, state) => CustomerPaymentScreen(
                        customerId: state.pathParameters['customerId']!,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
        StatefulShellBranch(
          navigatorKey: moreNavigatorKey,
          routes: <RouteBase>[
            GoRoute(
              path: AppRoutes.more,
              name: AppRouteNames.more,
              builder: (_, _) => const MoreScreen(),
            ),
          ],
        ),
      ],
    ),
    GoRoute(
      path: AppRoutes.settings,
      name: AppRouteNames.settings,
      builder: (_, _) => const SettingsScreen(),
      routes: <RouteBase>[
        GoRoute(
          path: 'business',
          name: AppRouteNames.settingsBusiness,
          builder: (_, _) => const BusinessProfileScreen(),
        ),
        GoRoute(
          path: 'receipt',
          name: AppRouteNames.settingsReceipt,
          builder: (_, _) => const ReceiptDesignerScreen(),
          routes: <RouteBase>[
            GoRoute(
              path: 'designer',
              name: AppRouteNames.receiptDesigner,
              builder: (_, _) => const ReceiptDesignerScreen(),
            ),
          ],
        ),
        GoRoute(
          path: 'tax',
          name: AppRouteNames.settingsTax,
          builder: (_, _) => const TaxCurrencyScreen(),
        ),
        GoRoute(
          path: 'printer',
          name: AppRouteNames.settingsPrinter,
          builder: (_, _) => const PrinterSettingsScreen(),
        ),
        GoRoute(
          path: 'profile',
          name: AppRouteNames.settingsProfile,
          builder: (_, _) => const ProfileSettingsScreen(),
        ),
        GoRoute(
          path: 'team',
          name: AppRouteNames.settingsTeam,
          builder: (_, state) => TeamScreen(key: state.pageKey),
        ),
        GoRoute(
          path: 'branches',
          name: AppRouteNames.settingsBranches,
          builder: (_, state) => BusinessBranchesScreen(key: state.pageKey),
        ),
        GoRoute(
          path: 'categories',
          name: AppRouteNames.settingsCategories,
          builder: (_, _) => const CategoriesSettingsScreen(),
        ),
        GoRoute(
          path: 'units',
          name: AppRouteNames.settingsUnits,
          builder: (_, _) => const UnitsSettingsScreen(),
        ),
        GoRoute(
          path: 'inventory',
          name: AppRouteNames.settingsInventory,
          builder: (_, _) => const InventorySettingsScreen(),
        ),
        GoRoute(
          path: 'security',
          name: AppRouteNames.settingsSecurity,
          builder: (_, _) => const SecuritySettingsScreen(),
        ),
        GoRoute(
          path: 'deletion-requests',
          name: AppRouteNames.deletionRequests,
          builder: (_, _) => const DeletionRequestsScreen(),
        ),
        GoRoute(
          path: 'notifications',
          name: AppRouteNames.settingsNotifications,
          builder: (_, _) => const NotificationsSettingsScreen(),
        ),
        GoRoute(
          path: 'billing',
          name: AppRouteNames.billing,
          builder: (_, _) => const BillingScreen(),
        ),
        GoRoute(
          path: 'release-readiness',
          name: AppRouteNames.releaseReadiness,
          builder: (_, state) => ReleaseReadinessScreen(key: state.pageKey),
        ),
      ],
    ),
    GoRoute(
      path: AppRoutes.expenses,
      name: AppRouteNames.expenses,
      builder: (_, state) => ExpensesScreen(key: state.pageKey),
      routes: <RouteBase>[
        GoRoute(
          path: 'new',
          name: AppRouteNames.newExpense,
          builder: (_, state) => ExpenseFormScreen(
            key: state.pageKey,
            initialAmount: state.uri.queryParameters['amount'],
            initialDescription: state.uri.queryParameters['description'],
            initialCategoryName: state.uri.queryParameters['category'],
          ),
        ),
        GoRoute(
          path: 'categories',
          name: AppRouteNames.expenseCategories,
          builder: (_, state) => ExpenseCategoriesScreen(key: state.pageKey),
        ),
        GoRoute(
          path: ':expenseId',
          name: AppRouteNames.expenseDetails,
          builder: (context, state) => ExpenseDetailsScreen(
            key: state.pageKey,
            expenseId: state.pathParameters['expenseId']!,
          ),
          routes: <RouteBase>[
            GoRoute(
              path: 'edit',
              name: AppRouteNames.editExpense,
              builder: (context, state) => ExpenseFormScreen(
                key: state.pageKey,
                expenseId: state.pathParameters['expenseId'],
              ),
            ),
          ],
        ),
      ],
    ),
    GoRoute(
      path: AppRoutes.suppliers,
      name: AppRouteNames.suppliers,
      builder: (_, state) => SuppliersScreen(key: state.pageKey),
      routes: <RouteBase>[
        GoRoute(
          path: 'new',
          name: AppRouteNames.newSupplier,
          builder: (_, state) => SupplierFormScreen(
            key: state.pageKey,
            initialName: state.uri.queryParameters['name'],
            initialPhone: state.uri.queryParameters['phone'],
          ),
        ),
        GoRoute(
          path: ':supplierId',
          name: AppRouteNames.supplierDetails,
          builder: (context, state) => SupplierDetailsScreen(
            key: state.pageKey,
            supplierId: state.pathParameters['supplierId']!,
          ),
          routes: <RouteBase>[
            GoRoute(
              path: 'edit',
              name: AppRouteNames.editSupplier,
              builder: (context, state) => SupplierFormScreen(
                key: state.pageKey,
                supplierId: state.pathParameters['supplierId'],
              ),
            ),
            GoRoute(
              path: 'payment',
              name: AppRouteNames.supplierPayment,
              builder: (context, state) => SupplierPaymentScreen(
                key: state.pageKey,
                supplierId: state.pathParameters['supplierId']!,
              ),
            ),
          ],
        ),
      ],
    ),
    GoRoute(
      path: AppRoutes.purchases,
      name: AppRouteNames.purchases,
      builder: (_, state) => PurchasesScreen(key: state.pageKey),
      routes: <RouteBase>[
        GoRoute(
          path: 'new',
          name: AppRouteNames.newPurchase,
          builder: (_, state) => NewPurchaseScreen(
            key: state.pageKey,
            preselectedSupplierId: state.uri.queryParameters['supplierId'],
            sabiQuery: state.uri.queryParameters['q'],
          ),
        ),
        GoRoute(
          path: ':purchaseId',
          name: AppRouteNames.purchaseDetails,
          builder: (context, state) => PurchaseDetailsScreen(
            key: state.pageKey,
            purchaseId: state.pathParameters['purchaseId']!,
          ),
          routes: <RouteBase>[
            GoRoute(
              path: 'return',
              name: AppRouteNames.purchaseReturn,
              builder: (context, state) => PurchaseReturnScreen(
                key: state.pageKey,
                purchaseId: state.pathParameters['purchaseId']!,
              ),
            ),
          ],
        ),
      ],
    ),
    // Legacy /sabi URLs → sales-branch draft (avoids root push over StatefulShell).
    GoRoute(
      path: AppRoutes.sabiAssistant,
      redirect: (context, state) {
        final params = state.uri.queryParameters;
        final q = params['q'];
        final voice = params['voice'];
        final buffer = StringBuffer(AppRoutes.sabiSaleDraft);
        final parts = <String>[
          if (q != null && q.isNotEmpty) 'q=${Uri.encodeQueryComponent(q)}',
          if (voice != null && voice.isNotEmpty)
            'voice=${Uri.encodeQueryComponent(voice)}',
        ];
        if (parts.isNotEmpty) {
          buffer.write('?${parts.join('&')}');
        }
        return buffer.toString();
      },
    ),
    GoRoute(
      path: '/sabi/sale-draft',
      redirect: (context, state) {
        final params = state.uri.queryParameters;
        final q = params['q'];
        final voice = params['voice'];
        final buffer = StringBuffer(AppRoutes.sabiSaleDraft);
        final parts = <String>[
          if (q != null && q.isNotEmpty) 'q=${Uri.encodeQueryComponent(q)}',
          if (voice != null && voice.isNotEmpty)
            'voice=${Uri.encodeQueryComponent(voice)}',
        ];
        if (parts.isNotEmpty) {
          buffer.write('?${parts.join('&')}');
        }
        return buffer.toString();
      },
    ),
    GoRoute(
      path: AppRoutes.notifications,
      name: AppRouteNames.notifications,
      builder: (_, state) => NotificationsScreen(key: state.pageKey),
    ),
    GoRoute(
      path: AppRoutes.attention,
      builder: (_, state) => AttentionScreen(key: state.pageKey),
    ),
    GoRoute(
      path: AppRoutes.activity,
      builder: (_, _) => const ModulePlaceholderScreen(
        title: 'Activity',
        description:
            'Your latest sales, expenses and stock updates will appear here.',
        icon: Icons.history_outlined,
      ),
    ),
    GoRoute(
      path: AppRoutes.reports,
      name: AppRouteNames.reports,
      builder: (_, state) => ReportsScreen(key: state.pageKey),
      routes: <RouteBase>[
        GoRoute(
          path: 'profit-loss',
          name: AppRouteNames.reportProfitLoss,
          builder: (_, state) => ProfitLossReportScreen(key: state.pageKey),
        ),
        GoRoute(
          path: 'product-profit',
          name: AppRouteNames.reportProductProfit,
          builder: (_, state) => ProductProfitReportScreen(key: state.pageKey),
        ),
        GoRoute(
          path: 'product-expiry',
          name: AppRouteNames.reportProductExpiry,
          builder: (_, state) => ProductExpiryReportScreen(key: state.pageKey),
        ),
        GoRoute(
          path: 'inventory',
          name: AppRouteNames.reportInventory,
          builder: (_, state) =>
              InventoryValuationReportScreen(key: state.pageKey),
        ),
        GoRoute(
          path: 'customers',
          name: AppRouteNames.reportCustomerBalances,
          builder: (_, state) =>
              CustomerBalancesReportScreen(key: state.pageKey),
        ),
        GoRoute(
          path: 'suppliers',
          name: AppRouteNames.reportSupplierBalances,
          builder: (_, state) =>
              SupplierBalancesReportScreen(key: state.pageKey),
        ),
        GoRoute(
          path: 'daily-summary/:dateKey',
          name: AppRouteNames.dailySummary,
          builder: (context, state) => DailySummaryScreen(
            key: state.pageKey,
            dateKey:
                state.pathParameters['dateKey'] ??
                BusinessSummaryService.dateKeyFor(DateTime.now()),
          ),
        ),
        GoRoute(
          path: 'weekly/:weekKey',
          name: AppRouteNames.weeklyReport,
          builder: (context, state) => WeeklyReportScreen(
            key: state.pageKey,
            weekKey:
                state.pathParameters['weekKey'] ??
                BusinessSummaryService.weekKeyFor(DateTime.now()),
          ),
        ),
        GoRoute(
          path: 'end-of-day/:dateKey',
          name: AppRouteNames.endOfDay,
          builder: (context, state) => EndOfDayScreen(
            key: state.pageKey,
            dateKey: state.pathParameters['dateKey'],
          ),
        ),
      ],
    ),
    GoRoute(
      path: AppRoutes.backup,
      name: AppRouteNames.backup,
      builder: (_, state) => BackupScreen(key: state.pageKey),
    ),
    GoRoute(
      path: AppRoutes.help,
      name: AppRouteNames.help,
      builder: (_, state) => HelpHomeScreen(key: state.pageKey),
      routes: <RouteBase>[
        GoRoute(
          path: 'faq',
          name: AppRouteNames.helpFaq,
          builder: (_, state) => HelpFaqScreen(key: state.pageKey),
        ),
        GoRoute(
          path: 'feedback',
          name: AppRouteNames.helpFeedback,
          builder: (_, state) => HelpFeedbackScreen(key: state.pageKey),
        ),
        GoRoute(
          path: 'contact',
          name: AppRouteNames.helpContact,
          builder: (_, state) => HelpContactScreen(key: state.pageKey),
        ),
        GoRoute(
          path: 'report-problem',
          name: AppRouteNames.helpReportProblem,
          builder: (_, state) => HelpFeedbackScreen(
            key: state.pageKey,
            initialCategory: FeedbackCategory.bug,
          ),
        ),
      ],
    ),
    GoRoute(
      path: AppRoutes.about,
      name: AppRouteNames.about,
      builder: (_, state) => AboutSabiBomScreen(key: state.pageKey),
    ),
    GoRoute(
      path: AppRoutes.team,
      name: AppRouteNames.team,
      builder: (_, state) => TeamScreen(key: state.pageKey),
      routes: <RouteBase>[
        GoRoute(
          path: 'invite',
          name: AppRouteNames.teamInvite,
          builder: (_, state) => InviteStaffScreen(key: state.pageKey),
        ),
        GoRoute(
          path: 'activity',
          name: AppRouteNames.teamActivity,
          builder: (_, state) => StaffActivityScreen(key: state.pageKey),
        ),
        GoRoute(
          path: 'roles',
          name: AppRouteNames.teamRoles,
          builder: (_, state) => TeamRolesScreen(key: state.pageKey),
          routes: <RouteBase>[
            GoRoute(
              path: 'new',
              name: AppRouteNames.teamRoleNew,
              builder: (_, state) => EditRoleScreen(key: state.pageKey),
            ),
            GoRoute(
              path: ':roleId/edit',
              name: AppRouteNames.teamRoleEdit,
              builder: (context, state) => EditRoleScreen(
                key: state.pageKey,
                roleId: state.pathParameters['roleId'],
              ),
            ),
          ],
        ),
        GoRoute(
          path: ':uid',
          name: AppRouteNames.teamMember,
          builder: (context, state) => StaffDetailsScreen(
            key: state.pageKey,
            uid: state.pathParameters['uid']!,
          ),
          routes: <RouteBase>[
            GoRoute(
              path: 'edit-role',
              name: AppRouteNames.teamMemberEditRole,
              builder: (context, state) => EditMemberRoleScreen(
                key: state.pageKey,
                uid: state.pathParameters['uid']!,
              ),
            ),
            GoRoute(
              path: 'permissions',
              name: AppRouteNames.teamMemberPermissions,
              builder: (context, state) => EditMemberPermissionsScreen(
                key: state.pageKey,
                uid: state.pathParameters['uid']!,
              ),
            ),
          ],
        ),
      ],
    ),
    GoRoute(
      path: AppRoutes.invite,
      name: AppRouteNames.invite,
      builder: (_, state) => AcceptInvitationScreen(key: state.pageKey),
      routes: <RouteBase>[
        GoRoute(
          path: ':invitationId',
          name: AppRouteNames.inviteWithId,
          builder: (context, state) => AcceptInvitationScreen(
            key: state.pageKey,
            invitationId: state.pathParameters['invitationId'],
          ),
        ),
      ],
    ),
    GoRoute(
      path: AppRoutes.approvals,
      name: AppRouteNames.approvals,
      builder: (_, state) => ApprovalsScreen(key: state.pageKey),
      routes: <RouteBase>[
        GoRoute(
          path: 'settings',
          name: AppRouteNames.approvalSettings,
          builder: (_, state) => ApprovalSettingsScreen(key: state.pageKey),
        ),
        GoRoute(
          path: ':approvalId',
          name: AppRouteNames.approvalDetails,
          builder: (context, state) => ApprovalDetailsScreen(
            key: state.pageKey,
            approvalId: state.pathParameters['approvalId']!,
          ),
        ),
      ],
    ),
    GoRoute(
      path: AppRoutes.myRole,
      name: AppRouteNames.myRole,
      builder: (_, state) => MyRoleScreen(key: state.pageKey),
    ),
    GoRoute(
      path: AppRoutes.accessDenied,
      builder: (_, state) => AccessDeniedScreen(key: state.pageKey),
    ),
    GoRoute(
      path: AppRoutes.privacy,
      name: AppRouteNames.privacy,
      builder: (_, _) => const PrivacyPolicyScreen(),
    ),
    GoRoute(
      path: AppRoutes.terms,
      name: AppRouteNames.terms,
      builder: (_, _) => const TermsScreen(),
    ),
  ],
);

class _AuthRefreshNotifier extends ChangeNotifier {
  _AuthRefreshNotifier._() {
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((
      value,
    ) {
      user = value;
      isResolved = true;
      notifyListeners();
    });
  }

  static final _AuthRefreshNotifier instance = _AuthRefreshNotifier._();

  var isResolved = false;
  User? user;
  late final StreamSubscription<User?> _authSubscription;

  @override
  void dispose() {
    _authSubscription.cancel();
    super.dispose();
  }
}
