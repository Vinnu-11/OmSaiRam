import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../firebase_assignments/data/firebase_assignment_models.dart';
import '../../firebase_groups/data/firebase_group_models.dart';

typedef FirebaseHighlightsBinding = ({String uid, String groupId});

String highlightText(String value, String label, int maximum) {
  if (value.trim().isEmpty || value.length > maximum) {
    throw FormatException('$label must be nonblank and at most $maximum characters.');
  }
  return value;
}

String highlightReportDetails(String value) {
  if (value.length > 1000) {
    throw const FormatException('Report details must be at most 1000 characters.');
  }
  return value;
}

enum FirebaseHighlightReportReason { spam, harassment, inappropriate, other }

/// User-supplied anchors, NOT verified scripture or canonical assignment units.
class FirebaseHighlightDraft {
  final int chapterNumber, paragraphIndex;
  final String quote, text;
  FirebaseHighlightDraft(this.chapterNumber, this.paragraphIndex, this.quote, this.text) {
    if (chapterNumber < 1 || chapterNumber > 53) {
      throw const FormatException('Original chapter number must be 1–53.');
    }
    if (paragraphIndex < 0 || paragraphIndex > 2147483647) {
      throw const FormatException('Paragraph index must be 0–2147483647.');
    }
    highlightText(quote, 'Quote', 500);
    highlightText(text, 'Comment', 2000);
  }
}

class FirebaseHighlightCursor {
  final Timestamp createdAt;
  final String id;
  FirebaseHighlightCursor(this.createdAt, String id) : id = assignmentSegment(id);
}

// Firestore ID ordering is UTF-8 byte ordering (not UTF-16 string ordering).
int highlightIdCompare(String a, String b) {
  final left = utf8.encode(a), right = utf8.encode(b);
  for (var i = 0; i < left.length && i < right.length; i++) {
    final comparison = left[i].compareTo(right[i]);
    if (comparison != 0) return comparison;
  }
  return left.length.compareTo(right.length);
}

/// Positive means a follows b in the descending query. Never convert to DateTime.
int highlightCursorCompare(FirebaseHighlightCursor a, FirebaseHighlightCursor b) {
  final seconds = b.createdAt.seconds.compareTo(a.createdAt.seconds);
  if (seconds != 0) return seconds;
  final nanos = b.createdAt.nanoseconds.compareTo(a.createdAt.nanoseconds);
  return nanos != 0 ? nanos : highlightIdCompare(b.id, a.id);
}

class FirebaseHighlight {
  final String groupId, id, senderUid, quote, text;
  final int chapterNumber, paragraphIndex;
  final Timestamp createdAt;
  const FirebaseHighlight._(this.groupId, this.id, this.senderUid,
      this.chapterNumber, this.paragraphIndex, this.quote, this.text, this.createdAt);
  factory FirebaseHighlight.parse(String groupId, String id, Map<String, dynamic>? raw) {
    assignmentSegment(groupId);
    assignmentSegment(id);
    final data = exactData(raw, {
      'senderUid', 'chapterNumber', 'paragraphIndex', 'quote', 'text', 'createdAt'
    });
    final sender = assignmentSegment(textField(data, 'senderUid', 1500));
    final draft = FirebaseHighlightDraft(
      intField(data, 'chapterNumber', 1, 53),
      intField(data, 'paragraphIndex', 0, 2147483647),
      textField(data, 'quote', 500), textField(data, 'text', 2000));
    final timestamp = data['createdAt'];
    if (timestamp is! Timestamp) {
      throw const FormatException('Confirmed server highlight timestamp required.');
    }
    return FirebaseHighlight._(groupId, id, sender, draft.chapterNumber,
      draft.paragraphIndex, draft.quote, draft.text, timestamp);
  }
  FirebaseHighlightCursor get cursor => FirebaseHighlightCursor(createdAt, id);
}

class FirebaseHighlightsPage {
  final String uid, groupId;
  final bool archived;
  final List<FirebaseHighlight> highlights;
  FirebaseHighlightsPage(this.uid, this.groupId, Iterable<FirebaseHighlight> highlights, {this.archived = false})
      : highlights = List.unmodifiable(highlights);
  FirebaseHighlightCursor? get cursor => highlights.isEmpty ? null : highlights.last.cursor;
  bool hasMore(int pageSize) => highlights.length == pageSize;
  void validate(FirebaseHighlightsBinding binding, int pageSize, FirebaseHighlightCursor? after) {
    assignmentSegment(binding.uid);
    assignmentSegment(binding.groupId);
    boundedPageSize(pageSize);
    if (uid != binding.uid || groupId != binding.groupId || highlights.length > pageSize) {
      throw const FormatException('Highlights page scope or size mismatch.');
    }
    final ids = <String>{};
    var previous = after;
    for (final highlight in highlights) {
      if (highlight.groupId != groupId || !ids.add(highlight.id) ||
          (previous != null && highlightCursorCompare(highlight.cursor, previous) <= 0)) {
        throw const FormatException('Invalid highlights page order, duplicate or scope.');
      }
      previous = highlight.cursor;
    }
  }
}

enum FirebaseHighlightDelivery { notAttempted, acknowledged, uncertain }
class FirebaseHighlightDeliveryUncertain implements Exception {
  const FirebaseHighlightDeliveryUncertain();
}
String highlightsError(Object error) => error is FormatException ? error.message
    : 'Highlights unavailable. Check your membership and connection, then refresh.';
const highlightUncertainMessage = 'Delivery uncertain: verify by refreshing newest highlights before retrying. Do not automatically resend.';