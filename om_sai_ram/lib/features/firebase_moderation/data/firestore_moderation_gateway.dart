import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../firebase_assignments/data/firebase_assignment_models.dart';
import '../../firebase_groups/data/firebase_group_models.dart';
import '../../firebase_chat/data/firebase_chat_models.dart';
import 'firebase_moderation_models.dart';

abstract class FirebaseModerationGateway {
  Future<FirebaseGroupRole> role(String groupId);
  Future<FirebaseModerationPage> read(String groupId, String messageId,
    {int pageSize = 20, String? after, FirebaseModerationTargetKind kind = FirebaseModerationTargetKind.messages});
  Future<void> resolve(String groupId, String messageId, String reporterUid, FirebaseReportStatus status,
    {FirebaseModerationTargetKind kind = FirebaseModerationTargetKind.messages});
  Future<void> remove(String groupId, String messageId, FirebaseReportReason reason,
    {FirebaseModerationTargetKind kind = FirebaseModerationTargetKind.messages});
}

final firebaseModerationGatewayProvider = Provider<FirebaseModerationGateway>((ref) {
  throw StateError('Firebase moderation bootstrap has not completed.');
});

/// Only the injected named-app SDK pair is used. Rules independently authorize writes.
class FirestoreModerationGateway implements FirebaseModerationGateway {
  final FirebaseAuth _auth;
  final FirebaseFirestore _db;
  FirestoreModerationGateway(this._auth, this._db);
  static const _server = GetOptions(source: Source.server);
  String _uid() => assignmentSegment(_auth.currentUser?.uid ?? '');
  void _same(String uid) {
    if (_auth.currentUser?.uid != uid) throw StateError('Firebase account changed.');
  }
  Future<T> _checked<T>(String uid, Future<T> Function() operation) async {
    _same(uid);
    try {
      final result = await operation();
      _same(uid);
      return result;
    } catch (_) { _same(uid); rethrow; }
  }
  void _confirmed(SnapshotMetadata metadata) {
    if (metadata.isFromCache || metadata.hasPendingWrites) throw StateError('Confirmed server data required.');
  }
  void _document(DocumentSnapshot<Map<String, dynamic>> doc, String path) {
    _confirmed(doc.metadata);
    if (doc.reference.path != path || doc.id != path.split('/').last) {
      throw const FormatException('Server document path mismatch.');
    }
  }
  Future<DocumentSnapshot<Map<String, dynamic>>> _get(String uid,
      DocumentReference<Map<String, dynamic>> doc) async {
    final result = await _checked(uid, () => doc.get(_server));
    _document(result, doc.path);
    return result;
  }
  DocumentReference<Map<String, dynamic>> _member(String group, String uid) =>
    _db.collection('groups').doc(group).collection('members').doc(uid);
  DocumentReference<Map<String, dynamic>> _target(String group, String id, FirebaseModerationTargetKind kind) =>
    _db.collection('groups').doc(group).collection(kind.name).doc(id);
  DocumentReference<Map<String, dynamic>> _marker(String group, String id, FirebaseModerationTargetKind kind) =>
    _db.collection('groups').doc(group).collection('moderationRecords').doc(kind.name).collection('items').doc(id);
  Future<FirebaseGroupRole> _role(String uid, String group) async =>
    FirebaseMembership.parse(uid, (await _get(uid, _member(group, uid))).data()).role;
  Future<void> _admin(String uid, String group) async {
    final role = await _checked(uid, () => _role(uid, group));
    if (role != FirebaseGroupRole.admin) throw const FormatException('Current group admin membership required.');
  }
  Future<void> _writable(Transaction transaction, String uid, String groupId) async {
    final reference = _db.collection('groups').doc(groupId);
    final snapshot = await _checked(uid, () => transaction.get(reference));
    _document(snapshot, reference.path);
    FirebaseGroup.parse(groupId, snapshot.data()).requireWritable();
  }
  @override
  Future<FirebaseGroupRole> role(String groupId) async {
    assignmentSegment(groupId);
    final uid = _uid();
    return _checked(uid, () => _role(uid, groupId));
  }
  @override
  Future<FirebaseModerationPage> read(String groupId, String messageId,
      {int pageSize = 20, String? after, FirebaseModerationTargetKind kind = FirebaseModerationTargetKind.messages}) async {
    assignmentSegment(groupId); assignmentSegment(messageId); boundedPageSize(pageSize);
    if (after != null) assignmentSegment(after);
    final uid = _uid();
    await _checked(uid, () => _admin(uid, groupId));
    final groupDoc = await _get(uid, _db.collection('groups').doc(groupId));
    final parsedGroup = FirebaseGroup.parse(groupId, groupDoc.data());
    final target = _target(groupId, messageId, kind), marker = _marker(groupId, messageId, kind);
    final item = await _get(uid, target);
    final audit = await _get(uid, marker);
    Query<Map<String, dynamic>> query = target.collection('reports')
      .orderBy(FieldPath.documentId).limit(pageSize);
    if (after != null) query = query.startAfter([after]);
    final snapshot = await _checked(uid, () => query.get(_server));
    _confirmed(snapshot.metadata);
    final reports = snapshot.docs.map((doc) {
      _document(doc, '${target.path}/reports/${assignmentSegment(doc.id)}');
      return FirebaseModerationReport.parse(doc.id, doc.data());
    });
    final page = FirebaseModerationPage((uid: uid, groupId: groupId, messageId: messageId),
      null, audit.exists ? FirebaseMessageModerationRecord.parse(messageId, audit.data(), kind: kind) : null,
      reports, kind: kind, archived: parsedGroup.archived,
      target: item.exists ? FirebaseModerationTarget.parse(kind, groupId, messageId, item.data()) : null);
    page.validate(page.binding, pageSize, after, expectedKind: kind);
    _same(uid);
    return page;
  }
  @override
  Future<void> resolve(String groupId, String messageId, String reporterUid, FirebaseReportStatus status,
      {FirebaseModerationTargetKind kind = FirebaseModerationTargetKind.messages}) async {
    assignmentSegment(groupId); assignmentSegment(messageId); assignmentSegment(reporterUid);
    if (status == FirebaseReportStatus.open) throw const FormatException('Reports cannot be reopened.');
    final uid = _uid();
    await _checked(uid, () => _admin(uid, groupId));
    final report = _target(groupId, messageId, kind).collection('reports').doc(reporterUid);
    final existing = await _get(uid, report);
    if (FirebaseModerationReport.parse(reporterUid, existing.data()).status != FirebaseReportStatus.open) {
      throw const FormatException('Report has already been handled.');
    }
    await _checked(uid, () => _db.runTransaction((transaction) async {
      await _writable(transaction, uid, groupId);
      final member = await _checked(uid, () => transaction.get(_member(groupId, uid)));
      _document(member, _member(groupId, uid).path);
      if (FirebaseMembership.parse(uid, member.data()).role != FirebaseGroupRole.admin) {
        throw const FormatException('Current group admin membership required.');
      }
      final current = await _checked(uid, () => transaction.get(report));
      _document(current, report.path);
      if (FirebaseModerationReport.parse(reporterUid, current.data()).status != FirebaseReportStatus.open) {
        throw const FormatException('Report has already been handled.');
      }
      _same(uid);
      transaction.update(report, {'status': status.name, 'resolvedBy': uid,
        'resolvedAt': FieldValue.serverTimestamp()});
    }));
  }
  @override
  Future<void> remove(String groupId, String messageId, FirebaseReportReason reason,
      {FirebaseModerationTargetKind kind = FirebaseModerationTargetKind.messages}) async {
    assignmentSegment(groupId); assignmentSegment(messageId);
    final uid = _uid();
    await _checked(uid, () => _admin(uid, groupId));
    final target = _target(groupId, messageId, kind), marker = _marker(groupId, messageId, kind);
    await _checked(uid, () => _db.runTransaction((transaction) async {
      await _writable(transaction, uid, groupId);
      final member = await _checked(uid, () => transaction.get(_member(groupId, uid)));
      _document(member, _member(groupId, uid).path);
      if (FirebaseMembership.parse(uid, member.data()).role != FirebaseGroupRole.admin) {
        throw const FormatException('Current group admin membership required.');
      }
      final item = await _checked(uid, () => transaction.get(target));
      _document(item, target.path);
      final audit = await _checked(uid, () => transaction.get(marker));
      _document(audit, marker.path);
      if (audit.exists) {
        FirebaseMessageModerationRecord.parse(messageId, audit.data(), kind: kind);
        throw FormatException('${kind.name} target has already been moderated.');
      }
      if (!item.exists) throw FormatException('${kind.name} target removed/unavailable.');
      final message = FirebaseModerationTarget.parse(kind, groupId, messageId, item.data());
      _same(uid);
      transaction.set(marker, {'targetKind': kind.name, 'targetId': messageId,
        'authorUid': message.senderUid, 'moderatedBy': uid,
        'moderatedAt': FieldValue.serverTimestamp(), 'reason': reason.name});
      transaction.delete(target);
    }));
  }
}