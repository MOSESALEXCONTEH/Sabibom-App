import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/auth_repository.dart';
import '../domain/app_user.dart';
import '../domain/auth_failure.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) => AuthRepository());

enum AuthOperation { email, google, facebook }

class AuthState {
  const AuthState({
    this.activeOperations = const <AuthOperation>{},
    this.errorMessage,
    this.user,
  });

  final Set<AuthOperation> activeOperations;
  final String? errorMessage;
  final AppUser? user;

  bool isLoading(AuthOperation operation) => activeOperations.contains(operation);

  AuthState copyWith({
    Set<AuthOperation>? activeOperations,
    String? errorMessage,
    bool clearError = false,
    AppUser? user,
    bool clearUser = false,
  }) => AuthState(
    activeOperations: activeOperations ?? this.activeOperations,
    errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    user: clearUser ? null : user ?? this.user,
  );
}

class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() => const AuthState();

  AuthRepository get _repository => ref.read(authRepositoryProvider);

  Future<void> signInWithEmail(String email, String password) => _run(
    AuthOperation.email,
    () async => _completeUser(
      await _repository.signInWithEmail(email: email, password: password),
    ),
  );

  Future<void> registerWithEmail(String fullName, String email, String password) => _run(
    AuthOperation.email,
    () async => _completeUser(
      await _repository.registerWithEmail(
        fullName: fullName,
        email: email,
        password: password,
      ),
    ),
  );

  Future<void> signInWithGoogle() => _run(AuthOperation.google, () async {
    final user = await _repository.signInWithGoogle();
    if (user != null) {
      _completeUser(user);
    }
  });

  Future<void> signInWithFacebook() => _run(AuthOperation.facebook, () async {
    final user = await _repository.signInWithFacebook();
    if (user != null) {
      _completeUser(user);
    }
  });

  Future<void> signOut() async {
    await _repository.signOut();
    state = const AuthState();
  }

  Future<void> _run(AuthOperation operation, Future<void> Function() action) async {
    if (state.isLoading(operation)) {
      return;
    }
    _setLoading(operation, true);
    try {
      await action();
    } on AuthFailure catch (failure) {
      if (!failure.isCancellation) {
        state = state.copyWith(errorMessage: failure.message);
      }
    } finally {
      _setLoading(operation, false);
    }
  }

  void _completeUser(AppUser user) {
    state = state.copyWith(
      user: user,
      clearError: true,
    );
  }

  void _setLoading(AuthOperation operation, bool isLoading) {
    final operations = <AuthOperation>{...state.activeOperations};
    if (isLoading) {
      operations.add(operation);
    } else {
      operations.remove(operation);
    }
    state = state.copyWith(activeOperations: operations, clearError: isLoading);
  }
}

final authControllerProvider = NotifierProvider<AuthController, AuthState>(AuthController.new);