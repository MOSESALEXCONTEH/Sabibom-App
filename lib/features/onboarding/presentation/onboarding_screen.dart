import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/services/onboarding_service.dart';
import '../domain/onboarding_item.dart';
import 'widgets/onboarding_page.dart';

/// Three-page product introduction presented to unauthenticated users.
class OnboardingScreen extends StatefulWidget {
  /// Creates the onboarding experience.
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  static const _systemUiStyle = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFF0B0914),
    systemNavigationBarDividerColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.light,
  );

  final PageController _pageController = PageController();
  final _onboarding = OnboardingService();
  var _currentPage = 0;
  var _isNavigating = false;
  var _didPrecacheImages = false;

  static const _items = <OnboardingItem>[
    OnboardingItem(
      imagePath: 'assets/images/slide-1.png',
      title: 'Your business in one place',
      description:
          'SabiBom helps you record sales, create receipts, track stock, manage expenses and understand your business.',
    ),
    OnboardingItem(
      imagePath: 'assets/images/slide-2.png',
      title: 'Clear numbers you can trust',
      description:
          'See sales, stock, customers and expenses clearly. Totals come from your real business records.',
    ),
    OnboardingItem(
      imagePath: 'assets/images/slide-3.png',
      title: 'Meet Sabi',
      description:
          'Sabi helps you prepare business records and understand verified business information. You always review before anything is saved.',
    ),
  ];

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(_systemUiStyle);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didPrecacheImages) return;
    _didPrecacheImages = true;
    for (final item in _items) {
      precacheImage(AssetImage(item.imagePath), context);
    }
  }

  @override
  void dispose() {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarDividerColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
    );
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _finishAndGo(String route) async {
    if (_isNavigating) return;
    setState(() => _isNavigating = true);
    await _onboarding.complete();
    if (!mounted) return;
    context.go(route);
  }

  Future<void> _handlePrimaryAction() async {
    if (_isNavigating) return;
    if (_currentPage == _items.length - 1) {
      await _finishAndGo(AppRoutes.register);
      return;
    }

    setState(() => _isNavigating = true);
    await _pageController.nextPage(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
    );
    if (mounted) setState(() => _isNavigating = false);
  }

  void _goToLogin() {
    _finishAndGo(AppRoutes.login);
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: _systemUiStyle,
      child: Scaffold(
        backgroundColor: Colors.black,
        extendBody: true,
        body: PageView.builder(
          controller: _pageController,
          itemCount: _items.length,
          onPageChanged: (page) => setState(() => _currentPage = page),
          itemBuilder: (context, index) => OnboardingPage(
            item: _items[index],
            isActive: index == _currentPage,
            currentPage: _currentPage,
            itemCount: _items.length,
            isLastPage: index == _items.length - 1,
            isLoading: _isNavigating,
            onPrimaryAction: _handlePrimaryAction,
            onLogin: _goToLogin,
          ),
        ),
      ),
    );
  }
}
