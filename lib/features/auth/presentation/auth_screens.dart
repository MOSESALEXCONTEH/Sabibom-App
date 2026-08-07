import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../app/router.dart';
import '../../../core/theme/app_spacing.dart';
import '../application/auth_controller.dart';
import '../data/remembered_login_store.dart';
import '../../../core/widgets/app_logo.dart';

class LoginScreen extends ConsumerStatefulWidget {
  /// Creates the login screen.
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _rememberedLoginStore = RememberedLoginStore();
  var _rememberMe = false;

  @override
  void initState() {
    super.initState();
    _loadRememberedLogin();
  }

  Future<void> _loadRememberedLogin() async {
    final remembered = await _rememberedLoginStore.load();
    if (!mounted) return;
    setState(() {
      _emailController.text = remembered.email;
      _rememberMe = remembered.enabled;
    });
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;
    await _rememberedLoginStore.save(
      email: _emailController.text,
      enabled: _rememberMe,
    );
    await ref
        .read(authControllerProvider.notifier)
        .signInWithEmail(_emailController.text, _passwordController.text);
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AuthState>(authControllerProvider, (_, next) {
      _showError(context, next.errorMessage);
    });
    final state = ref.watch(authControllerProvider);
    return _AuthScaffold(
      title: 'Welcome back',
      subtitle: 'Sign in to manage your business.',
      actionLabel: 'Sign in',
      secondaryLabel: 'Create an account',
      formKey: _formKey,
      emailController: _emailController,
      passwordController: _passwordController,
      rememberMe: _rememberMe,
      onRememberMeChanged: (value) => setState(() => _rememberMe = value),
      isLoading: state.isLoading(AuthOperation.email),
      isGoogleLoading: state.isLoading(AuthOperation.google),
      isFacebookLoading: state.isLoading(AuthOperation.facebook),
      onAction: _signIn,
      onGoogle: () =>
          ref.read(authControllerProvider.notifier).signInWithGoogle(),
      onFacebook: () =>
          ref.read(authControllerProvider.notifier).signInWithFacebook(),
      onSecondaryAction: () => context.go(AppRoutes.register),
    );
  }
}

class RegisterScreen extends ConsumerStatefulWidget {
  /// Creates the registration screen.
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AuthState>(authControllerProvider, (_, next) {
      _showError(context, next.errorMessage);
    });
    final state = ref.watch(authControllerProvider);
    return _AuthScaffold(
      title: 'Build your business hub',
      subtitle: 'Create an account to get started with SabiBom.',
      actionLabel: 'Create account',
      secondaryLabel: 'I already have an account',
      formKey: _formKey,
      nameController: _nameController,
      emailController: _emailController,
      passwordController: _passwordController,
      isLoading: state.isLoading(AuthOperation.email),
      isGoogleLoading: state.isLoading(AuthOperation.google),
      isFacebookLoading: state.isLoading(AuthOperation.facebook),
      onAction: () {
        if (_formKey.currentState!.validate()) {
          ref
              .read(authControllerProvider.notifier)
              .registerWithEmail(
                _nameController.text,
                _emailController.text,
                _passwordController.text,
              );
        }
      },
      onGoogle: () =>
          ref.read(authControllerProvider.notifier).signInWithGoogle(),
      onFacebook: () =>
          ref.read(authControllerProvider.notifier).signInWithFacebook(),
      onSecondaryAction: () => context.go(AppRoutes.login),
    );
  }
}

class _AuthScaffold extends StatelessWidget {
  const _AuthScaffold({
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.secondaryLabel,
    required this.formKey,
    required this.emailController,
    required this.passwordController,
    required this.isLoading,
    required this.isGoogleLoading,
    required this.isFacebookLoading,
    required this.onAction,
    required this.onGoogle,
    required this.onFacebook,
    required this.onSecondaryAction,
    this.nameController,
    this.rememberMe,
    this.onRememberMeChanged,
  });

  final String title;
  final String subtitle;
  final String actionLabel;
  final String secondaryLabel;
  final GlobalKey<FormState> formKey;
  final TextEditingController? nameController;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final bool? rememberMe;
  final ValueChanged<bool>? onRememberMeChanged;
  final bool isLoading;
  final bool isGoogleLoading;
  final bool isFacebookLoading;
  final VoidCallback onAction;
  final VoidCallback onGoogle;
  final VoidCallback onFacebook;
  final VoidCallback onSecondaryAction;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - (AppSpacing.lg * 2),
                ),
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Center(child: AppLogo(size: 88)),
                      const SizedBox(height: AppSpacing.xl),
                      Text(
                        title,
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      if (nameController != null) ...<Widget>[
                        TextFormField(
                          controller: nameController,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(
                            labelText: 'Full name',
                          ),
                          validator: (value) =>
                              value == null || value.trim().length < 2
                              ? 'Enter your full name.'
                              : null,
                        ),
                        const SizedBox(height: AppSpacing.md),
                      ],
                      TextFormField(
                        controller: emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: 'Email address',
                        ),
                        validator: (value) =>
                            value == null ||
                                !RegExp(
                                  r'^\S+@\S+\.\S+$',
                                ).hasMatch(value.trim())
                            ? 'Enter a valid email address.'
                            : null,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      TextFormField(
                        controller: passwordController,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Password',
                        ),
                        validator: (value) => value == null || value.length < 6
                            ? 'Use a password with at least six characters.'
                            : null,
                      ),
                      if (rememberMe != null) ...<Widget>[
                        const SizedBox(height: AppSpacing.sm),
                        CheckboxListTile(
                          value: rememberMe,
                          onChanged: (value) =>
                              onRememberMeChanged?.call(value ?? false),
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          title: const Text('Remember me'),
                          subtitle: const Text(
                            'Remember my email on this device',
                          ),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.lg),
                      FilledButton(
                        onPressed: isLoading ? null : onAction,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(52),
                        ),
                        child: isLoading
                            ? const SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(actionLabel),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      const Row(
                        children: <Widget>[
                          Expanded(child: Divider()),
                          Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: AppSpacing.md,
                            ),
                            child: Text('OR'),
                          ),
                          Expanded(child: Divider()),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      OutlinedButton.icon(
                        onPressed: isGoogleLoading ? null : onGoogle,
                        icon: SvgPicture.asset(
                          'assets/images/google_g_logo.svg',
                          width: 20,
                          height: 20,
                        ),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(52),
                        ),
                        label: isGoogleLoading
                            ? const SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Continue with Google'),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Semantics(
                        button: true,
                        label: 'Continue with Facebook',
                        child: FilledButton.icon(
                          onPressed: isFacebookLoading ? null : onFacebook,
                          icon: SvgPicture.asset(
                            'assets/images/facebook_f_logo.svg',
                            width: 20,
                            height: 20,
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF1877F2),
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(52),
                          ),
                          label: isFacebookLoading
                              ? const SizedBox.square(
                                  dimension: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text('Continue with Facebook'),
                        ),
                      ),
                      Center(
                        child: TextButton(
                          onPressed: onSecondaryAction,
                          child: Text(secondaryLabel),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

void _showError(BuildContext context, String? message) {
  if (message == null) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
