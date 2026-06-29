// Om Sai Ram
// Utility extensions and helper functions.

/// Validation helpers for form fields.
class Validators {
  Validators._();

  /// Validates an email address format.
  static String? email(String? value) {
    if (value == null || value.isEmpty) {
      return 'Email is required';
    }
    if (value.length > 254) {
      return 'Email is too long';
    }
    final emailRegex = RegExp(
      r'^[a-zA-Z0-9.!#$%&*+/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$',
    );
    if (!emailRegex.hasMatch(value)) {
      return 'Please enter a valid email';
    }
    return null;
  }

  /// Validates password strength (minimum 8 characters).
  static String? password(String? value) {
    if (value == null || value.isEmpty) {
      return 'Password is required';
    }
    if (value.length < 8) {
      return 'Password must be at least 8 characters';
    }
    if (value.length > 128) {
      return 'Password is too long';
    }
    return null;
  }

  /// Validates that confirm password matches the original.
  static String? confirmPassword(String? value, String password) {
    if (value == null || value.isEmpty) {
      return 'Please confirm your password';
    }
    if (value != password) {
      return 'Passwords do not match';
    }
    return null;
  }

  /// Validates a non-empty required field with optional max length.
  static String? required(String? value, [String fieldName = 'This field']) {
    if (value == null || value.trim().isEmpty) {
      return '$fieldName is required';
    }
    if (value.trim().length > 100) {
      return '$fieldName is too long (max 100 characters)';
    }
    return null;
  }

  /// Validates a group name with length constraints.
  static String? groupName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Group name is required';
    }
    if (value.trim().length < 2) {
      return 'Group name must be at least 2 characters';
    }
    if (value.trim().length > 80) {
      return 'Group name is too long (max 80 characters)';
    }
    return null;
  }

  /// Validates an invite code format.
  static String? inviteCode(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Invite code is required';
    }
    if (value.trim().length < 4) {
      return 'Invite code is too short';
    }
    if (value.trim().length > 20) {
      return 'Invite code is too long';
    }
    return null;
  }
}
