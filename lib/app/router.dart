import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'app_shell.dart';
import '../features/auth/presentation/auth_screens.dart';
import '../features/business_profile/presentation/business_profile_screen.dart';
import '../features/business_setup/presentation/business_setup_choice_screen.dart';
import '../features/business_setup/presentation/business_setup_screen.dart';
import '../features/dashboard/presentation/dashboard_screen.dart';
import '../features/more/presentation/more_screen.dart';
import '../features/onboarding/presentation/onboarding_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/shell/presentation/module_placeholder_screen.dart';
import '../features/sales/data/sales_repository.dart';
import '../features/sales/presentation/sales_screens.dart';
import '../features/splash/splash_screen.dart';

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
  static const expenses = '/expenses';
  static const sabiAssistant = '/sabi';
  static const notifications = '/notifications';
  static const activity = '/activity';
  static const reports = '/reports';
  static const help = '/help';
  static const about = '/about';
}

final GoRouter appRouter = GoRouter(
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
      if (location == AppRoutes.splash || guestRoutes.contains(location)) {
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
          routes: <RouteBase>[
            GoRoute(
              path: AppRoutes.home,
              builder: (_, _) => const DashboardScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: <RouteBase>[
            GoRoute(
              path: AppRoutes.sales,
              builder: (_, _) => const SalesScreen(),
              routes: <RouteBase>[
                GoRoute(path: 'new', builder: (_, _) => const NewSaleScreen()),
                GoRoute(
                  path: 'checkout',
                  builder: (_, _) => const CheckoutScreen(),
                ),
                GoRoute(
                  path: 'success/:saleId',
                  builder: (_, state) => SaleCompleteScreen(
                    saleId: state.pathParameters['saleId']!,
                    completed: state.extra as CompletedSale?,
                  ),
                ),
                GoRoute(
                  path: ':saleId/receipt',
                  builder: (_, state) => DigitalReceiptScreen(
                    saleId: state.pathParameters['saleId']!,
                  ),
                ),
              ],
            ),
          ],
        ),
        StatefulShellBranch(
          routes: <RouteBase>[
            GoRoute(
              path: AppRoutes.products,
              builder: (_, _) => const ModulePlaceholderScreen(
                title: 'Products',
                description:
                    'Manage your products, stock levels and prices from here.',
                icon: Icons.inventory_2_outlined,
              ),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: <RouteBase>[
            GoRoute(
              path: AppRoutes.customers,
              builder: (_, _) => const ModulePlaceholderScreen(
                title: 'Customers',
                description:
                    'Keep customer contacts and balances organized from here.',
                icon: Icons.people_outline,
              ),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: <RouteBase>[
            GoRoute(
              path: AppRoutes.more,
              builder: (_, _) => const MoreScreen(),
            ),
          ],
        ),
      ],
    ),
    GoRoute(
      path: AppRoutes.settings,
      builder: (_, _) => const SettingsScreen(),
    ),
    GoRoute(
      path: AppRoutes.expenses,
      builder: (_, _) => const ModulePlaceholderScreen(
        title: 'Expenses',
        description: 'Record and review business expenses from here.',
        icon: Icons.payments_outlined,
      ),
    ),
    GoRoute(
      path: AppRoutes.sabiAssistant,
      builder: (_, _) => const ModulePlaceholderScreen(
        title: 'Ask Sabi',
        description:
            'Sabi will use your business data once its AI service is connected.',
        icon: Icons.auto_awesome_outlined,
      ),
    ),
    GoRoute(
      path: AppRoutes.notifications,
      builder: (_, _) => const ModulePlaceholderScreen(
        title: 'Notifications',
        description: 'Important business updates will appear here.',
        icon: Icons.notifications_outlined,
      ),
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
      builder: (_, _) => const ModulePlaceholderScreen(
        title: 'Reports',
        description: 'Business reports will be available here soon.',
        icon: Icons.bar_chart_outlined,
      ),
    ),
    GoRoute(
      path: AppRoutes.help,
      builder: (_, _) => const ModulePlaceholderScreen(
        title: 'Help and Support',
        description: 'Support resources will be available here soon.',
        icon: Icons.support_agent_outlined,
      ),
    ),
    GoRoute(
      path: AppRoutes.about,
      builder: (_, _) => const ModulePlaceholderScreen(
        title: 'About SabiBom',
        description: 'SabiBom helps small businesses operate with confidence.',
        icon: Icons.info_outline,
      ),
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
