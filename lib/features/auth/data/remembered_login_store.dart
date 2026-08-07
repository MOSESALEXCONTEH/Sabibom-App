import 'package:shared_preferences/shared_preferences.dart';

class RememberedLogin {
  const RememberedLogin({required this.email, required this.enabled});

  final String email;
  final bool enabled;
}

class RememberedLoginStore {
  static const _emailKey = 'remembered_login_email_v1';

  Future<RememberedLogin> load() async {
    final preferences = await SharedPreferences.getInstance();
    final email = preferences.getString(_emailKey)?.trim() ?? '';
    return RememberedLogin(email: email, enabled: email.isNotEmpty);
  }

  Future<void> save({required String email, required bool enabled}) async {
    final preferences = await SharedPreferences.getInstance();
    if (!enabled) {
      await preferences.remove(_emailKey);
      return;
    }
    await preferences.setString(_emailKey, email.trim());
  }
}
