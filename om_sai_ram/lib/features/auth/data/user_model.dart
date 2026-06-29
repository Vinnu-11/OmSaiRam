// Om Sai Ram
// User model — represents an authenticated user.

import 'package:equatable/equatable.dart';

/// Represents a user in the system.
///
/// Used across the app to display user info and manage permissions.
class User extends Equatable {
  final String id;
  final String email;
  final String name;
  final String? avatarUrl;
  final String authProvider; // 'email', 'google', 'apple'
  final DateTime createdAt;

  const User({
    required this.id,
    required this.email,
    required this.name,
    this.avatarUrl,
    required this.authProvider,
    required this.createdAt,
  });

  /// Creates a User from JSON response data.
  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String,
      email: json['email'] as String,
      name: json['name'] as String,
      avatarUrl: json['avatar_url'] as String?,
      authProvider: json['auth_provider'] as String? ?? 'email',
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  /// Converts this User to a JSON map.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'name': name,
      'avatar_url': avatarUrl,
      'auth_provider': authProvider,
      'created_at': createdAt.toIso8601String(),
    };
  }

  @override
  List<Object?> get props => [id, email, name, avatarUrl, authProvider];
}
