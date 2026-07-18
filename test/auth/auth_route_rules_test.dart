import 'package:flutter_test/flutter_test.dart';
import 'package:sabibom/features/auth/application/auth_route_rules.dart';

const _guestRoutes = <String>{'/login', '/register', '/onboarding'};
const _protectedRoutes = <String>{
  '/dashboard',
  '/settings',
};

void main() {
  test('keeps guest routes accessible while logged out', () {
    expect(
      authRouteRedirect(
        isAuthenticated: false,
        location: '/login',
        onboardingRoute: '/onboarding',
        dashboardRoute: '/dashboard',
        guestOnlyRoutes: _guestRoutes,
        protectedRoutes: _protectedRoutes,
      ),
      isNull,
    );
  });

  test('redirects logged-out users from protected routes', () {
    expect(
      authRouteRedirect(
        isAuthenticated: false,
        location: '/dashboard',
        onboardingRoute: '/onboarding',
        dashboardRoute: '/dashboard',
        guestOnlyRoutes: _guestRoutes,
        protectedRoutes: _protectedRoutes,
      ),
      '/onboarding',
    );
  });

  test('prevents authenticated users returning to login', () {
    expect(
      authRouteRedirect(
        isAuthenticated: true,
        location: '/login',
        onboardingRoute: '/onboarding',
        dashboardRoute: '/dashboard',
        guestOnlyRoutes: _guestRoutes,
        protectedRoutes: _protectedRoutes,
      ),
      '/dashboard',
    );
  });
}
