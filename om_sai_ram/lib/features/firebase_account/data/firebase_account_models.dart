import 'package:cloud_firestore/cloud_firestore.dart';
import '../../firebase_assignments/data/firebase_assignment_models.dart';
import '../../firebase_auth/data/firebase_auth_repository.dart';
import '../../firebase_groups/data/firebase_group_models.dart';

const passwordResetRequested =
    'If an eligible account exists, reset instructions have been requested. Check your email.';
const passwordResetEmulatorNotice =
    'Auth emulator only: no real email is sent. Reset action links are available to the developer in local emulator tooling.';

String resetEmail(String input) {
  final email = input.trim();
  if (email.length > 254 ||
      !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
    throw const FormatException('Enter a valid email address.');
  }
  return email;
}

/// Private users/{SDK uid} only; never an Auth or public group profile.
class FirebasePrivateProfile {
  final String uid, displayName;
  final Timestamp createdAt, updatedAt;
  const FirebasePrivateProfile._(
      this.uid, this.displayName, this.createdAt, this.updatedAt);
  factory FirebasePrivateProfile.parse(String uid, Map<String, dynamic>? raw) {
    assignmentSegment(uid);
    final data = exactData(raw, {'displayName', 'createdAt', 'updatedAt'});
    final name = data['displayName'];
    if (name is! String || validateDisplayName(name) != name) {
      throw const FormatException('Invalid private display name.');
    }
    Timestamp timestamp(String field) {
      final value = data[field];
      if (value is! Timestamp || value.seconds < -62135596800 ||
          value.seconds > 253402300799 || value.nanoseconds < 0 ||
          value.nanoseconds > 999999999) {
        throw const FormatException('Invalid private profile Timestamp.');
      }
      return value;
    }
    return FirebasePrivateProfile._(
        uid, name, timestamp('createdAt'), timestamp('updatedAt'));
  }
}