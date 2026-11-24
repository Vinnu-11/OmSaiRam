import 'package:cloud_firestore/cloud_firestore.dart';
import '../../firebase_assignments/data/firebase_assignment_models.dart';
import '../../firebase_groups/data/firebase_group_models.dart';
import '../../firebase_chat/data/firebase_chat_models.dart';
import '../../firebase_highlights/data/firebase_highlight_models.dart';

typedef FirebaseModerationBinding = ({String uid, String groupId, String messageId});
enum FirebaseModerationTargetKind { messages, highlights }
typedef FirebaseModerationTargetBinding = ({FirebaseModerationBinding scope, FirebaseModerationTargetKind kind});

/// Keeps the original models intact; a highlight is never a chat message.
sealed class FirebaseModerationTarget {
  const FirebaseModerationTarget();
  FirebaseModerationTargetKind get kind;
  String get groupId;
  String get id;
  String get senderUid;
  String get text;
  Timestamp get createdAt;
  static FirebaseModerationTarget parse(FirebaseModerationTargetKind kind,
      String group, String id, Map<String, dynamic>? raw) => switch (kind) {
    FirebaseModerationTargetKind.messages => FirebaseModerationMessage(FirebaseChatMessage.parse(group, id, raw)),
    FirebaseModerationTargetKind.highlights => FirebaseModerationHighlight(FirebaseHighlight.parse(group, id, raw)),
  };
}
final class FirebaseModerationMessage extends FirebaseModerationTarget {
  final FirebaseChatMessage message;
  const FirebaseModerationMessage(this.message);
  @override FirebaseModerationTargetKind get kind => FirebaseModerationTargetKind.messages;
  @override String get groupId => message.groupId;
  @override String get id => message.id;
  @override String get senderUid => message.senderUid;
  @override String get text => message.text;
  @override Timestamp get createdAt => message.createdAt;
}
final class FirebaseModerationHighlight extends FirebaseModerationTarget {
  final FirebaseHighlight highlight;
  const FirebaseModerationHighlight(this.highlight);
  @override FirebaseModerationTargetKind get kind => FirebaseModerationTargetKind.highlights;
  @override String get groupId => highlight.groupId;
  @override String get id => highlight.id;
  @override String get senderUid => highlight.senderUid;
  @override String get text => highlight.text;
  @override Timestamp get createdAt => highlight.createdAt;
}

void moderationScope(FirebaseModerationBinding scope) {
  assignmentSegment(scope.uid);
  assignmentSegment(scope.groupId);
  assignmentSegment(scope.messageId);
}

Timestamp moderationTime(Map<String, dynamic> data, String key) {
  final value = data[key];
  if (value is! Timestamp) throw FormatException('Invalid server $key timestamp.');
  return value;
}

enum FirebaseReportStatus { open, resolved, dismissed }

FirebaseReportReason moderationReason(Object? value) => FirebaseReportReason.values.firstWhere(
  (reason) => reason.name == value,
  orElse: () => throw const FormatException('Invalid moderation reason.'));

class FirebaseModerationReport {
  final String reporterUid, details;
  final FirebaseReportReason reason;
  final Timestamp createdAt;
  final FirebaseReportStatus status;
  final String? resolvedBy;
  final Timestamp? resolvedAt;
  const FirebaseModerationReport._(this.reporterUid, this.details, this.reason,
    this.createdAt, this.status, this.resolvedBy, this.resolvedAt);
  factory FirebaseModerationReport.parse(String reporter, Map<String, dynamic>? raw) {
    assignmentSegment(reporter);
    final data = exactData(raw, {'reporterUid', 'reason', 'details', 'createdAt',
      'status', 'resolvedBy', 'resolvedAt'});
    if (data['reporterUid'] != reporter) throw const FormatException('Report path identity mismatch.');
    final status = FirebaseReportStatus.values.firstWhere((s) => s.name == data['status'],
      orElse: () => throw const FormatException('Invalid report status.'));
    String? by;
    Timestamp? at;
    if (status == FirebaseReportStatus.open) {
      if (data['resolvedBy'] != null || data['resolvedAt'] != null) {
        throw const FormatException('Open report cannot have resolution fields.');
      }
    } else {
      by = assignmentSegment(textField(data, 'resolvedBy', 1500));
      at = moderationTime(data, 'resolvedAt');
    }
    return FirebaseModerationReport._(reporter,
      textField(data, 'details', 1000, nonempty: false), moderationReason(data['reason']),
      moderationTime(data, 'createdAt'), status, by, at);
  }
}

class FirebaseMessageModerationRecord {
  final FirebaseModerationTargetKind kind;
  final String messageId, authorUid, moderatedBy;
  final Timestamp moderatedAt;
  final FirebaseReportReason reason;
  const FirebaseMessageModerationRecord._(this.kind, this.messageId, this.authorUid,
    this.moderatedBy, this.moderatedAt, this.reason);
  factory FirebaseMessageModerationRecord.parse(String id, Map<String, dynamic>? raw,
      {FirebaseModerationTargetKind kind = FirebaseModerationTargetKind.messages}) {
    assignmentSegment(id);
    final data = exactData(raw, {'targetKind', 'targetId', 'authorUid',
      'moderatedBy', 'moderatedAt', 'reason'});
    if (data['targetKind'] != kind.name || data['targetId'] != id) {
      throw const FormatException('Moderation marker target mismatch.');
    }
    return FirebaseMessageModerationRecord._(kind, id,
      assignmentSegment(textField(data, 'authorUid', 1500)),
      assignmentSegment(textField(data, 'moderatedBy', 1500)),
      moderationTime(data, 'moderatedAt'), moderationReason(data['reason']));
  }
}

class FirebaseModerationPage {
  final FirebaseModerationBinding binding;
  final bool archived;
  final FirebaseModerationTargetKind kind;
  final FirebaseModerationTarget? target;
  final FirebaseMessageModerationRecord? marker;
  final List<FirebaseModerationReport> reports;
  FirebaseModerationPage(this.binding, FirebaseChatMessage? message, this.marker,
    Iterable<FirebaseModerationReport> reports,
    {this.kind = FirebaseModerationTargetKind.messages, FirebaseModerationTarget? target, this.archived = false})
      : target = target ?? (message == null ? null : FirebaseModerationMessage(message)),
        reports = List.unmodifiable(reports) {
    if (message != null && target != null) throw const FormatException('Ambiguous moderation target.');
  }
  String? get cursor => reports.isEmpty ? null : reports.last.reporterUid;
  bool hasMore(int size) => reports.length == size;
  void validate(FirebaseModerationBinding expected, int size, String? after,
      {FirebaseModerationTargetKind expectedKind = FirebaseModerationTargetKind.messages}) {
    moderationScope(expected);
    boundedPageSize(size);
    if (after != null) assignmentSegment(after);
    if (binding != expected || kind != expectedKind || reports.length > size ||
      (target != null && target!.kind != expectedKind) ||
      (marker != null && marker!.kind != expectedKind) ||
        (target != null && (target!.groupId != expected.groupId || target!.id != expected.messageId)) ||
        (marker != null && marker!.messageId != expected.messageId) ||
        (target != null && marker != null)) {
      throw const FormatException('Moderation page scope or target state mismatch.');
    }
    var previous = after;
    for (final report in reports) {
      assignmentSegment(report.reporterUid);
      if (previous != null && chatIdCompare(report.reporterUid, previous) <= 0) {
        throw const FormatException('Invalid report order or duplicate.');
      }
      previous = report.reporterUid;
    }
  }
}

String moderationError(Object error) => error is FormatException ? error.message :
  'Moderation unavailable. Current group admin membership and a server connection are required. Refresh to verify access.';