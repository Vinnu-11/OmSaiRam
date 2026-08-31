// Om Sai Ram
// Auth repository — handles authentication API calls and token storage.

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/services/api_client.dart';
import 'user_model.dart';

/// Provider for the auth repository.
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(apiClient: ref.read(apiClientProvider));
});

/// Handles all authentication-related operations.
///
/// Responsibilities:
/// - Email/password registration and login
/// - Social authentication (Google/Apple) token exchange
/// - Token storage and retrieval
/// - Logout (clear tokens)
class AuthRepository {
  final ApiClient _apiClient;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  AuthRepository({required ApiClient apiClient}) : _apiClient = apiClient;

  /// Registers a new user with email and password.
  ///
  /// Returns the created [User] on success.
  /// Throws an exception with the error message on failure.
  Future<User> register({
    required String name,
    required String email,
    required String password,
    String? phoneNumber,
  }) async {
    final response = await _apiClient.post(
      AppConstants.registerEndpoint,
      data: {
        'name': name,
        'email': email,
        'password': password,
        if (phoneNumber != null) 'phone_number': phoneNumber,
      },
    );

    await _storeTokens(response.data);
    return User.fromJson(response.data['user']);
  }

  /// Logs in an existing user with email and password.
  ///
  /// Returns the [User] on success.
  Future<User> login({
    required String email,
    required String password,
  }) async {
    final response = await _apiClient.post(
      AppConstants.loginEndpoint,
      data: {
        'email': email,
        'password': password,
      },
    );

    await _storeTokens(response.data);
    return User.fromJson(response.data['user']);
  }

  /// Authenticates via social provider (Google or Apple).
  ///
  /// Exchanges the provider's ID token for our JWT tokens.
  /// Creates a new account if the user doesn't exist.
  Future<User> socialLogin({
    required String provider, // 'google' or 'apple'
    required String idToken,
    String? name,
  }) async {
    final response = await _apiClient.post(
      AppConstants.socialAuthEndpoint,
      data: {
        'provider': provider,
        'id_token': idToken,
        'name': name,
      },
    );

    await _storeTokens(response.data);
    return User.fromJson(response.data['user']);
  }

  /// Sends an OTP to the given phone number.
  /// Returns the number of minutes until the OTP expires.
  Future<int> sendPhoneOtp(String phoneNumber) async {
    final response = await _apiClient.post(
      AppConstants.phoneSendOtpEndpoint,
      data: {'phone_number': phoneNumber},
    );
    return response.data['expires_in_minutes'] as int? ?? 10;
  }

  /// Verifies the OTP. On success returns the authenticated [User].
  /// Pass [name] only when creating a new account (first sign-up).
  Future<User> verifyPhoneOtp({
    required String phoneNumber,
    required String otp,
    String? name,
  }) async {
    final response = await _apiClient.post(
      AppConstants.phoneVerifyOtpEndpoint,
      data: {
        'phone_number': phoneNumber,
        'otp': otp,
        if (name != null) 'name': name,
      },
    );
    await _storeTokens(response.data);
    return User.fromJson(response.data['user']);
  }

  /// Clears stored tokens and logs the user out.
  Future<void> logout() async {
    await _storage.delete(key: AppConstants.accessTokenKey);
    await _storage.delete(key: AppConstants.refreshTokenKey);
    await _storage.delete(key: AppConstants.userDataKey);
  }

  /// Checks if a valid access token exists in storage.
  Future<bool> hasValidToken() async {
    final token = await _storage.read(key: AppConstants.accessTokenKey);
    return token != null;
  }

  /// Fetches the current user from the backend using stored token.
  /// Returns null if the token is invalid or expired.
  Future<User?> getCurrentUser() async {
    try {
      final response = await _apiClient.get('/auth/me');
      return User.fromJson(response.data);
    } catch (_) {
      return null;
    }
  }

  /// Updates the current user's profile.
  Future<User> updateProfile(Map<String, dynamic> fields) async {
    final response = await _apiClient.patch('/auth/me', data: fields);
    return User.fromJson(response.data);
  }

  /// Changes the password for email-authenticated users.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    await _apiClient.post(
      AppConstants.changePasswordEndpoint,
      data: {
        'current_password': currentPassword,
        'new_password': newPassword,
      },
    );
  }

  /// Stores access and refresh tokens securely.
  Future<void> _storeTokens(Map<String, dynamic> data) async {
    await _storage.write(
      key: AppConstants.accessTokenKey,
      value: data['access_token'] as String,
    );
    await _storage.write(
      key: AppConstants.refreshTokenKey,
      value: data['refresh_token'] as String,
    );
  }
}
