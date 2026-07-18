import 'package:shared_preferences/shared_preferences.dart';

/// Persists whether the introductory product experience was completed.
class OnboardingService {
  /// Key used in local preferences.
  static const _completedKey = 'onboarding_completed';

  /// Reads the completion state, defaulting to false for first launch.
  Future<bool> isCompleted() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(_completedKey) ?? false;
  }

  /// Marks the onboarding flow as complete.
  Future<void> complete() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_completedKey, true);
  }
}
