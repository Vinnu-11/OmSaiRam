// Om Sai Ram
// Auth state provider — manages authentication state across the app.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/auth_repository.dart';
import '../data/user_model.dart';

/// Represents the current authentication state.
class AuthState {
  final User? user;
  final bool isLoading;
  final String? error;

  const AuthState({this.user, this.isLoading = false, this.error});

  /// Whether the user is currently authenticated.
  bool get isAuthenticated => user != null;

  AuthState copyWith({User? user, bool? isLoading, String? error}) {
    return AuthState(
      user: user ?? this.user,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

/// Global auth state provider — watched by the router for redirects.
final authStateProvider =
    StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(repository: ref.read(authRepositoryProvider));
});

/// Notifier that manages auth state transitions.
///
/// Handles login, signup, social auth, and logout.
/// The router watches this provider to redirect unauthenticated users.
class AuthNotifier extends StateNotifier<AuthState> {
  final AuthRepository _repository;

  AuthNotifier({required AuthRepository repository})
      : _repository = repository,
        super(const AuthState()) {
    _checkExistingToken();
  }

  /// On app start, checks if there's a stored token and validates it.
  Future<void> _checkExistingToken() async {
    try {
      final hasToken = await _repository.hasValidToken();
      if (!hasToken) {
        state = const AuthState();
        return;
      }
      // Try to fetch current user to validate the token
      final user = await _repository.getCurrentUser();
      if (user != null) {
        state = AuthState(user: user);
      } else {
        state = const AuthState();
      }
    } catch (_) {
      // Token invalid or network issue — stay unauthenticated
      state = const AuthState();
    }
  }

  /// Logs in with email and password.
  Future<void> login({required String email, required String password}) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final user = await _repository.login(email: email, password: password);
      state = AuthState(user: user);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: _parseError(e, _AuthFlow.login));
    }
  }

  /// Registers a new account with email and password.
  Future<void> signup({
    required String name,
    required String email,
    required String password,
    String? phoneNumber,
  }) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final user = await _repository.register(
        name: name,
        email: email,
        password: password,
        phoneNumber: phoneNumber,
      );
      state = AuthState(user: user);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: _parseError(e, _AuthFlow.signup));
    }
  }

  /// Sends an OTP to the given phone number.
  /// Returns the expiry duration in minutes on success, or throws.
  Future<int> sendPhoneOtp(String phoneNumber) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final expiryMinutes = await _repository.sendPhoneOtp(phoneNumber);
      state = state.copyWith(isLoading: false);
      return expiryMinutes;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: _parseError(e, _AuthFlow.sendOtp));
      rethrow;
    }
  }

  /// Verifies the OTP and logs in (or creates a new account if [name] is given).
  Future<void> verifyPhoneOtp({
    required String phoneNumber,
    required String otp,
    String? name,
  }) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final user = await _repository.verifyPhoneOtp(
        phoneNumber: phoneNumber,
        otp: otp,
        name: name,
      );
      state = AuthState(user: user);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: _parseError(e, _AuthFlow.verifyOtp));
    }
  }

  /// Authenticates with a social provider (Google/Apple).
  Future<void> socialLogin({
    required String provider,
    required String idToken,
    String? name,
  }) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final user = await _repository.socialLogin(
        provider: provider,
        idToken: idToken,
        name: name,
      );
      state = AuthState(user: user);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: _parseError(e, _AuthFlow.social));
    }
  }

  /// Logs out the current user and clears tokens.
  Future<void> logout() async {
    await _repository.logout();
    state = const AuthState();
  }

  /// Updates the current user's profile fields.
  Future<void> updateProfile(Map<String, dynamic> fields) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final user = await _repository.updateProfile(fields);
      state = AuthState(user: user);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
      rethrow;
    }
  }

  /// Changes the password for email-authenticated users.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      await _repository.changePassword(
        currentPassword: currentPassword,
        newPassword: newPassword,
      );
      state = state.copyWith(isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: _parseError(e, _AuthFlow.login));
      rethrow;
    }
  }

  /// Clears any displayed error.
  void clearError() {
    state = state.copyWith(error: null);
  }

  /// Extracts a user-friendly error message from exceptions.
  String _parseError(dynamic error, _AuthFlow flow) {
    final errStr = error.toString();

    // Network / connection errors
    if (errStr.contains('SocketException') ||
        errStr.contains('Connection refused') ||
        errStr.contains('Network is unreachable')) {
      return 'No internet connection. Please check your network.';
    }
    if (errStr.contains('TimeoutException') ||
        errStr.contains('connectTimeout') ||
        errStr.contains('receiveTimeout')) {
      return 'Connection timed out. Please try again.';
    }

    // HTTP status-specific errors — messages vary by flow
    if (errStr.contains('409')) {
      return 'An account with this email or mobile number already exists.';
    }
    if (errStr.contains('404')) {
      return flow == _AuthFlow.login
          ? 'No account found with this email. Please sign up.'
          : 'No account found for this number.';
    }
    if (errStr.contains('401')) {
      return flow == _AuthFlow.login
          ? 'Login failed. Please check your credentials and try again.'
          : 'Invalid or expired OTP. Please try again.';
    }
    if (errStr.contains('400')) {
      return flow == _AuthFlow.login
          ? 'Login failed. Please check your credentials and try again.'
          : 'Invalid details. Please check and try again.';
    }
    if (errStr.contains('422')) {
      return 'Please check your input and try again.';
    }
    if (errStr.contains('429')) {
      return 'Too many attempts. Please wait and try again.';
    }
    if (errStr.contains('500') || errStr.contains('503')) {
      return 'Server error. Please try again later.';
    }

    return 'Something went wrong. Please try again.';
  }
}

enum _AuthFlow { login, signup, sendOtp, verifyOtp, social }
