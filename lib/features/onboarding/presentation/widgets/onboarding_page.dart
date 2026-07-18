import 'package:flutter/material.dart';

import '../../../../core/widgets/app_logo.dart';
import '../../domain/onboarding_item.dart';
import 'onboarding_button.dart';
import 'onboarding_indicator.dart';

/// Full-screen image-led onboarding page with accessible overlay controls.
class OnboardingPage extends StatelessWidget {
  /// Creates an onboarding content page.
  const OnboardingPage({
    required this.item,
    required this.isActive,
    required this.currentPage,
    required this.itemCount,
    required this.isLastPage,
    required this.isLoading,
    required this.onPrimaryAction,
    required this.onLogin,
    super.key,
  });

  /// Content displayed by this page.
  final OnboardingItem item;

  /// Whether this page is currently visible.
  final bool isActive;

  /// Selected page index for the progress indicator.
  final int currentPage;

  /// Total number of onboarding pages.
  final int itemCount;

  /// Whether this page completes onboarding.
  final bool isLastPage;

  /// Prevents repeated navigation requests.
  final bool isLoading;

  /// Advances to the next page or begins registration.
  final VoidCallback onPrimaryAction;

  /// Opens the existing login screen.
  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final transitionDuration = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 380);
    return LayoutBuilder(
      builder: (context, constraints) {
        final isShortScreen = constraints.maxHeight < 680;
        final titleSize = isShortScreen ? 29.0 : 34.0;
        final descriptionSize = isShortScreen ? 16.0 : 18.0;
        final contentGap = isShortScreen ? 10.0 : 16.0;
        const textShadow = Shadow(
          color: Color(0xB3000000),
          blurRadius: 8,
          offset: Offset(0, 2),
        );

        return Stack(
          fit: StackFit.expand,
          children: <Widget>[
            Positioned.fill(
              child: Image.asset(
                item.imagePath,
                fit: BoxFit.cover,
                alignment: item.imageAlignment,
                errorBuilder: (_, _, _) => const ColoredBox(
                  color: Color(0xFF17122B),
                  child: Center(
                    child: Icon(
                      Icons.image_not_supported_outlined,
                      color: Colors.white70,
                      size: 56,
                    ),
                  ),
                ),
              ),
            ),
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[
                      Colors.transparent,
                      Color(0x1A000000),
                      Color(0xB3000000),
                      Color(0xE6000000),
                    ],
                    stops: <double>[0, .40, .72, 1],
                  ),
                ),
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                height: 112,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[Color(0x59000000), Colors.transparent],
                  ),
                ),
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      DecoratedBox(
                        decoration: const BoxDecoration(
                          boxShadow: <BoxShadow>[
                            BoxShadow(
                              color: Color(0x66000000),
                              blurRadius: 10,
                              offset: Offset(0, 3),
                            ),
                          ],
                        ),
                        child: const AppLogo(size: 48),
                      ),
                      TextButton(
                        onPressed: isLoading ? null : onLogin,
                        style: TextButton.styleFrom(
                          minimumSize: const Size(48, 48),
                          foregroundColor: Colors.white,
                          backgroundColor: const Color(0x33000000),
                          textStyle: const TextStyle(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        child: const Text('Skip'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 22),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: AnimatedOpacity(
                      opacity: isActive ? 1 : .45,
                      duration: transitionDuration,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(
                            item.title,
                            maxLines: isShortScreen ? 2 : 3,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.headlineMedium
                                ?.copyWith(
                                  color: Colors.white,
                                  fontSize: titleSize,
                                  fontWeight: FontWeight.w800,
                                  height: 1.12,
                                  shadows: const <Shadow>[textShadow],
                                ),
                          ),
                          SizedBox(height: contentGap),
                          Text(
                            item.description,
                            maxLines: isShortScreen ? 3 : 4,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyLarge
                                ?.copyWith(
                                  color: Colors.white.withValues(alpha: .80),
                                  fontSize: descriptionSize,
                                  height: 1.35,
                                  shadows: const <Shadow>[textShadow],
                                ),
                          ),
                          SizedBox(height: isShortScreen ? 16 : 24),
                          OnboardingIndicator(
                            currentPage: currentPage,
                            itemCount: itemCount,
                          ),
                          SizedBox(height: isShortScreen ? 16 : 22),
                          OnboardingButton(
                            label: isLastPage ? 'Get Started' : 'Next',
                            isLoading: isLoading,
                            onPressed: onPrimaryAction,
                          ),
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: isLoading ? null : onLogin,
                            child: Text.rich(
                              TextSpan(
                                text: 'Already have an account? ',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: .88),
                                  shadows: const <Shadow>[textShadow],
                                ),
                                children: const <InlineSpan>[
                                  TextSpan(
                                    text: 'Sign In',
                                    style: TextStyle(
                                      color: Color(0xFFC8B9FF),
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
