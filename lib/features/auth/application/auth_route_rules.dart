/// Determines the safe route for an authentication-state transition.
String? authRouteRedirect({
  required bool isAuthenticated,
  required String location,
  required String onboardingRoute,
  required String dashboardRoute,
  required Set<String> guestOnlyRoutes,
  required Set<String> protectedRoutes,
}) {
  if (!isAuthenticated && protectedRoutes.contains(location)) {
    return onboardingRoute;
  }
  if (isAuthenticated && guestOnlyRoutes.contains(location)) {
    return dashboardRoute;
  }
  return null;
}
