// Om Sai Ram
// API client service using Dio for HTTP communication with the backend.

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../constants/app_constants.dart';

/// Provider for the API client singleton.
final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient();
});

/// HTTP client wrapper around Dio.
///
/// Handles:
/// - Base URL configuration
/// - JWT token injection via interceptor
/// - Automatic token refresh on 401 responses
/// - Request/response logging in debug mode
class ApiClient {
  late final Dio _dio;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  ApiClient() {
    _dio = Dio(
      BaseOptions(
        baseUrl: AppConstants.apiBaseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );

    // Add auth interceptor to inject JWT token into requests
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await _storage.read(key: AppConstants.accessTokenKey);
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
        onError: (error, handler) async {
          // Attempt token refresh on 401 Unauthorized
          if (error.response?.statusCode == 401) {
            final refreshed = await _refreshToken();
            if (refreshed) {
              // Retry the original request with new token
              final token =
                  await _storage.read(key: AppConstants.accessTokenKey);
              error.requestOptions.headers['Authorization'] = 'Bearer $token';
              final response = await _dio.fetch(error.requestOptions);
              return handler.resolve(response);
            }
          }
          handler.next(error);
        },
      ),
    );
  }

  /// Attempts to refresh the access token using the stored refresh token.
  /// Returns true if refresh was successful.
  Future<bool> _refreshToken() async {
    try {
      final refreshToken =
          await _storage.read(key: AppConstants.refreshTokenKey);
      if (refreshToken == null) return false;

      final response = await Dio().post(
        '${AppConstants.apiBaseUrl}${AppConstants.refreshEndpoint}',
        data: {'refresh_token': refreshToken},
      );

      if (response.statusCode == 200) {
        await _storage.write(
          key: AppConstants.accessTokenKey,
          value: response.data['access_token'],
        );
        await _storage.write(
          key: AppConstants.refreshTokenKey,
          value: response.data['refresh_token'],
        );
        return true;
      }
    } catch (_) {
      // Refresh failed — user needs to re-login
    }
    return false;
  }

  // ─── HTTP Methods ─────────────────────────────────────────────────────

  /// Sends a GET request to [path] with optional [queryParameters].
  Future<Response> get(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) {
    return _dio.get(path, queryParameters: queryParameters);
  }

  /// Sends a POST request to [path] with optional [data] body.
  Future<Response> post(String path, {dynamic data}) {
    return _dio.post(path, data: data);
  }

  /// Sends a PUT request to [path] with optional [data] body.
  Future<Response> put(String path, {dynamic data}) {
    return _dio.put(path, data: data);
  }

  /// Sends a PATCH request to [path] with optional [data] body.
  Future<Response> patch(String path, {dynamic data}) {
    return _dio.patch(path, data: data);
  }

  /// Sends a DELETE request to [path].
  Future<Response> delete(String path) {
    return _dio.delete(path);
  }
}
