class SessionRouteState {
  const SessionRouteState({
    required this.isResolved,
    required this.isAuthenticated,
  });

  factory SessionRouteState.unresolved() {
    return const SessionRouteState(isResolved: false, isAuthenticated: false);
  }

  final bool isResolved;
  final bool isAuthenticated;
}

String? resolveAppRedirect({
  required SessionRouteState session,
  required String location,
  required String splashRoute,
  required String onboardingRoute,
  required String postAuthRoute,
  required Set<String> guestRoutes,
  required Set<String> protectedRoutes,
}) {
  if (!session.isResolved) {
    return location == splashRoute ? null : splashRoute;
  }

  if (!session.isAuthenticated) {
    if (location == splashRoute) return onboardingRoute;
    if (protectedRoutes.contains(location)) return onboardingRoute;
    return null;
  }

  if (location == splashRoute) {
    return postAuthRoute;
  }
  if (guestRoutes.contains(location)) return postAuthRoute;
  return null;
}
