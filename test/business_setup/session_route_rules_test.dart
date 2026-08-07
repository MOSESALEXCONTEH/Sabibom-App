import 'package:flutter_test/flutter_test.dart';
import 'package:sabibom/app/session_route_rules.dart';

const _guestRoutes = <String>{'/onboarding', '/login', '/register'};

const _protectedRoutes = <String>{'/dashboard', '/settings', '/business-setup'};

void main() {
  test('unresolved session stays on splash', () {
    expect(
      resolveAppRedirect(
        session: SessionRouteState.unresolved(),
        location: '/dashboard',
        splashRoute: '/',
        onboardingRoute: '/onboarding',
        postAuthRoute: '/app',
        guestRoutes: _guestRoutes,
        protectedRoutes: _protectedRoutes,
      ),
      '/',
    );
  });

  test('authenticated users reach the post-auth landing screen', () {
    expect(
      resolveAppRedirect(
        session: const SessionRouteState(
          isResolved: true,
          isAuthenticated: true,
        ),
        location: '/dashboard',
        splashRoute: '/',
        onboardingRoute: '/onboarding',
        postAuthRoute: '/app',
        guestRoutes: _guestRoutes,
        protectedRoutes: _protectedRoutes,
      ),
      isNull,
    );
  });

  test('authenticated users are redirected from guest routes', () {
    expect(
      resolveAppRedirect(
        session: const SessionRouteState(
          isResolved: true,
          isAuthenticated: true,
        ),
        location: '/login',
        splashRoute: '/',
        onboardingRoute: '/onboarding',
        postAuthRoute: '/app',
        guestRoutes: _guestRoutes,
        protectedRoutes: _protectedRoutes,
      ),
      '/app',
    );
  });
}
