import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/theme/app_spacing.dart';

/// Password and sign-in security for the account.
class SecuritySettingsScreen extends StatefulWidget {
  const SecuritySettingsScreen({super.key});

  @override
  State<SecuritySettingsScreen> createState() => _SecuritySettingsScreenState();
}

class _SecuritySettingsScreenState extends State<SecuritySettingsScreen> {
  final _currentPassword = TextEditingController();
  final _newPassword = TextEditingController();
  final _confirmPassword = TextEditingController();
  var _saving = false;
  var _obscure = true;

  @override
  void dispose() {
    _currentPassword.dispose();
    _newPassword.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final providers =
        user?.providerData.map((p) => p.providerId).toSet() ?? <String>{};
    final hasPassword = providers.contains('password');

    return Scaffold(
      appBar: AppBar(title: const Text('Security')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: <Widget>[
          Text(
            'Keep your SabiBom account safe. Use a strong password and only share '
            'device access with trusted staff.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.lg),
          Card(
            child: ListTile(
              leading: const Icon(Icons.mail_outline),
              title: const Text('Signed in as'),
              subtitle: Text(user?.email ?? 'No email on this account'),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Card(
            child: ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Data deletion requests'),
              subtitle: const Text(
                'Request deletion and track its review status',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.pushNamed(AppRouteNames.deletionRequests),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Card(
            child: ListTile(
              leading: const Icon(Icons.lock_outline),
              title: const Text('Sign-in methods'),
              subtitle: Text(
                providers.isEmpty
                    ? 'Unknown'
                    : providers.map(_providerLabel).join(', '),
              ),
            ),
          ),
          if (hasPassword) ...<Widget>[
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Change password',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _currentPassword,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: 'Current password',
                suffixIcon: IconButton(
                  onPressed: () => setState(() => _obscure = !_obscure),
                  icon: Icon(
                    _obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _newPassword,
              obscureText: _obscure,
              decoration: const InputDecoration(labelText: 'New password'),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _confirmPassword,
              obscureText: _obscure,
              decoration: const InputDecoration(
                labelText: 'Confirm new password',
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton(
              onPressed: _saving ? null : _changePassword,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
              child: _saving
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Update password'),
            ),
          ] else ...<Widget>[
            const SizedBox(height: AppSpacing.lg),
            const Card(
              child: ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('Social sign-in'),
                subtitle: Text(
                  'This account uses Google or Facebook. Manage password '
                  'security with that provider.',
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _providerLabel(String id) {
    switch (id) {
      case 'password':
        return 'Email & password';
      case 'google.com':
        return 'Google';
      case 'facebook.com':
        return 'Facebook';
      default:
        return id;
    }
  }

  Future<void> _changePassword() async {
    final user = FirebaseAuth.instance.currentUser;
    final email = user?.email;
    if (user == null || email == null) return;

    final current = _currentPassword.text;
    final next = _newPassword.text;
    final confirm = _confirmPassword.text;
    if (current.isEmpty || next.length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('New password must be at least 8 characters.'),
        ),
      );
      return;
    }
    if (next != confirm) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('New passwords do not match.')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final credential = EmailAuthProvider.credential(
        email: email,
        password: current,
      );
      await user.reauthenticateWithCredential(credential);
      await user.updatePassword(next);
      _currentPassword.clear();
      _newPassword.clear();
      _confirmPassword.clear();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Password updated.')));
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;
      final message = switch (error.code) {
        'wrong-password' ||
        'invalid-credential' => 'Current password is incorrect.',
        'requires-recent-login' =>
          'Please sign out and sign in again, then retry.',
        _ => 'Could not update password. Please try again.',
      };
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
