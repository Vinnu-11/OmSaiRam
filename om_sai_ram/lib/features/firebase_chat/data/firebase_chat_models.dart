import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../firebase_assignments/data/firebase_assignment_models.dart';
import '../../firebase_groups/data/firebase_group_models.dart';

typedef FirebaseChatBinding = ({String uid, String groupId});

String chatText(String text) {
  if (text.trim().isEmpty || text.length > 2000) {
    throw const FormatException('Message must be nonblank and at most 2000 characters.');
  }
  return text; // Preserve original text; validate before allocating an auto-ID.
}

String reportDetails(String text) {
  if (text.length > 1000) {
    throw const FormatException('Report details must be at most 1000 characters.');
  }
  return text;
}

enum FirebaseReportReason { spam, harassment, inappropriate, other }

class FirebaseChatCursor {
  final Timestamp createdAt;
  final String id;
  FirebaseChatCursor(this.createdAt, String id) : id = assignmentSegment(id);
}

// Firestore string ordering uses UTF-8 bytes, not Dart UTF-16 code units.
int chatIdCompare(String a, String b) {
  final left = utf8.encode(a), right = utf8.encode(b);
  for (var i = 0; i < left.length && i < right.length; i++) {
    final diff = left[i].compareTo(right[i]);
    if (diff != 0) return diff;
  }
  return left.length.compareTo(right.length);
}

/// Positive means a belongs AFTER b in the descending query.
int chatCursorCompare(FirebaseChatCursor a, FirebaseChatCursor b) {
  final seconds = b.createdAt.seconds.compareTo(a.createdAt.seconds);
  if (seconds != 0) return seconds;
  final nanos = b.createdAt.nanoseconds.compareTo(a.createdAt.nanoseconds);
  return nanos != 0 ? nanos : chatIdCompare(b.id, a.id);
}

class FirebaseChatMessage {
  final String groupId, id, senderUid, text;
  final Timestamp createdAt;
  const FirebaseChatMessage._(this.groupId, this.id, this.senderUid, this.text, this.createdAt);
  factory FirebaseChatMessage.parse(String groupId, String id, Map<String, dynamic>? raw) {
    assignmentSegment(groupId);
    assignmentSegment(id);
    final data = exactData(raw, {'senderUid', 'text', 'createdAt'});
    final sender = assignmentSegment(textField(data, 'senderUid', 1500));
    final text = chatText(textField(data, 'text', 2000));
    final timestamp = data['createdAt'];
    if (timestamp is! Timestamp) {
      throw const FormatException('Confirmed server message timestamp required.');
    }
    return FirebaseChatMessage._(groupId, id, sender, text, timestamp);
  }
  FirebaseChatCursor get cursor => FirebaseChatCursor(createdAt, id);
}

class FirebaseChatPage {
  final String uid, groupId;
  final bool archived;
  final List<FirebaseChatMessage> messages;
  FirebaseChatPage(this.uid, this.groupId, Iterable<FirebaseChatMessage> messages, {this.archived = false})
      : messages = List.unmodifiable(messages);
  FirebaseChatCursor? get cursor => messages.isEmpty ? null : messages.last.cursor;
  bool hasMore(int pageSize) => messages.length == pageSize;
  void validate(FirebaseChatBinding binding, int pageSize, FirebaseChatCursor? after) {
    assignmentSegment(binding.uid);
    assignmentSegment(binding.groupId);
    boundedPageSize(pageSize);
    if (uid != binding.uid || groupId != binding.groupId || messages.length > pageSize) {
      throw const FormatException('Chat page scope or size mismatch.');
    }
    final ids = <String>{};
    var previous = after;
    for (final message in messages) {
      if (message.groupId != groupId || !ids.add(message.id) ||
          (previous != null && chatCursorCompare(message.cursor, previous) <= 0)) {
        throw const FormatException('Invalid chat page order, duplicate or scope.');
      }
      previous = message.cursor;
    }
  }
}

enum FirebaseChatDelivery { notAttempted, acknowledged, uncertain }

class FirebaseChatDeliveryUncertain implements Exception {
  const FirebaseChatDeliveryUncertain();
}

String chatError(Object error) => error is FormatException
    ? error.message
    : 'Chat unavailable. Check your membership and connection, then refresh.';

const chatUncertainMessage = 'Delivery uncertain: verify by refreshing before retrying. Do not automatically resend.';