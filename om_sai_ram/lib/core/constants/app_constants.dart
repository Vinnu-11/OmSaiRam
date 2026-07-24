// Om Sai Ram
// API and configuration constants.

/// API and configuration constants.
/// Base URLs and endpoints are defined here for easy environment switching.
class AppConstants {
  AppConstants._();

  // API Configuration
  // Change this to your production URL when deploying
  static const String baseUrl = 'http://localhost:8000'; // Web/desktop dev
  static const String apiVersion = '/api/v1';
  static const String apiBaseUrl = '$baseUrl$apiVersion';

  // Auth endpoints
  static const String loginEndpoint = '/auth/login';
  static const String registerEndpoint = '/auth/register';
  static const String refreshEndpoint = '/auth/refresh';
  static const String socialAuthEndpoint = '/auth/social';
  static const String phoneSendOtpEndpoint = '/auth/phone/send-otp';
  static const String phoneVerifyOtpEndpoint = '/auth/phone/verify-otp';

  // Group endpoints
  static const String groupsEndpoint = '/groups';
  static const String joinGroupEndpoint = '/groups/join';

  // Content endpoints
  static const String contentVersionsEndpoint = '/content/versions';
  static const String chaptersEndpoint = '/content/chapters';

  // Festivals endpoint
  static const String festivalsEndpoint = '/festivals';

  // Assignment endpoints
  static const String assignmentsEndpoint = '/assignments';

  // Progress endpoints
  static const String progressEndpoint = '/progress';

  // Notification schedule endpoint (per-group)
  // Append '/{groupId}/notification-schedule' at call site.
  static const String groupNotificationScheduleEndpoint = '/groups';

  // Storage keys
  static const String accessTokenKey = 'access_token';
  static const String refreshTokenKey = 'refresh_token';
  static const String userDataKey = 'user_data';

  // Sai Satcharita
  static const int totalChapters = 50;
  static const int saptahDays = 7;

  // Pagination
  static const int defaultPageSize = 20;
}
