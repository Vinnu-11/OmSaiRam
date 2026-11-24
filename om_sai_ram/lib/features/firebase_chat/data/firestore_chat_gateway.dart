import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../firebase_auth/data/firebase_auth_repository.dart';
import '../../firebase_assignments/data/firebase_assignment_models.dart';
import '../../firebase_groups/data/firebase_group_models.dart';
import 'firebase_chat_models.dart';

abstract class FirebaseChatGateway {
  Future<FirebaseChatPage> read(String groupId, {int pageSize = 20, FirebaseChatCursor? after});
  /// Completion acknowledges the write only, not a subsequent history read.
  Future<void> send(String groupId, String text);
  Future<void> report(String groupId, String messageId, FirebaseReportReason reason, String details);
}

final firebaseChatGatewayProvider = Provider<FirebaseChatGateway>((ref) {
  throw StateError('Firebase chat bootstrap has not completed.');
});

/// Injected named-app SDK instances only; no default initialization/fallback.
class FirestoreChatGateway implements FirebaseChatGateway {
  final FirebaseAuth _auth;
  final FirebaseFirestore _db;
  FirestoreChatGateway(this._auth, this._db);
  static const _server = GetOptions(source: Source.server);

  String _uid() => assignmentSegment(_auth.currentUser?.uid ?? '');
  void _same(String uid) {
    if (_auth.currentUser?.uid != uid) throw StateError('Firebase account changed.');
  }
  Future<T> _checked<T>(String uid, Future<T> Function() operation) async {
    _same(uid);
    try {
      final value = await operation();
      _same(uid);
      return value;
    } catch (_) {
      _same(uid);
      rethrow;
    }
  }
  void _confirmed(SnapshotMetadata metadata) {
    if (metadata.isFromCache || metadata.hasPendingWrites) {
      throw StateError('Confirmed server data required.');
    }
  }
  void _document(DocumentSnapshot<Map<String, dynamic>> snapshot, String path) {
    _confirmed(snapshot.metadata);
    if (snapshot.reference.path != path || snapshot.id != path.split('/').last) {
      throw const FormatException('Server document path mismatch.');
    }
  }
  Future<DocumentSnapshot<Map<String, dynamic>>> _get(String uid, DocumentReference<Map<String, dynamic>> doc) async {
    final result = await _checked(uid, () => doc.get(_server));
    _document(result, doc.path);
    return result;
  }
  Future<FirebaseGroup> _access(String uid, String groupId) async {
    final profile = await _get(uid, _db.collection('users').doc(uid));
    final data = exactData(profile.data(), {'displayName', 'createdAt', 'updatedAt'});
    validateDisplayName(textField(data, 'displayName', 100));
    dateField(data, 'createdAt');
    dateField(data, 'updatedAt');
    final group = _db.collection('groups').doc(groupId);
    final parsedGroup = FirebaseGroup.parse(groupId, (await _get(uid, group)).data());
    FirebaseMembership.parse(uid, (await _get(uid, group.collection('members').doc(uid))).data());
    _same(uid);
    return parsedGroup;
  }
  CollectionReference<Map<String, dynamic>> _messages(String groupId) =>
      _db.collection('groups').doc(groupId).collection('messages');

  @override
  Future<FirebaseChatPage> read(String groupId, {int pageSize = 20, FirebaseChatCursor? after}) async {
    assignmentSegment(groupId);
    boundedPageSize(pageSize);
    if (after != null) assignmentSegment(after.id);
    final uid = _uid();
    final parsedGroup = await _access(uid, groupId);
    Query<Map<String, dynamic>> query = _messages(groupId)
        .orderBy('createdAt', descending: true)
        .orderBy(FieldPath.documentId, descending: true).limit(pageSize);
    if (after != null) query = query.startAfter([after.createdAt, after.id]);
    final snapshot = await _checked(uid, () => query.get(_server));
    _confirmed(snapshot.metadata);
    final rows = snapshot.docs.map((doc) {
      assignmentSegment(doc.id);
      _document(doc, '${_messages(groupId).path}/${doc.id}');
      return FirebaseChatMessage.parse(groupId, doc.id, doc.data());
    }).toList();
    final page = FirebaseChatPage(uid, groupId, rows, archived: parsedGroup.archived);
    page.validate((uid: uid, groupId: groupId), pageSize, after);
    _same(uid);
    return page;
  }

  @override
  Future<void> send(String groupId, String text) async {
    assignmentSegment(groupId);
    chatText(text);
    final uid = _uid();
    (await _access(uid, groupId)).requireWritable();
    _same(uid);
    final doc = _messages(groupId).doc();
    // Never retry auto-ID sends. Transport failure may follow a committed write.
    try {
      await _checked(uid, () => doc.set({
        'senderUid': uid, 'text': text, 'createdAt': FieldValue.serverTimestamp()
      }));
    } catch (_) {
      _same(uid);
      throw const FirebaseChatDeliveryUncertain();
    }
  }

  @override
  Future<void> report(String groupId, String messageId, FirebaseReportReason reason, String details) async {
    assignmentSegment(groupId);
    assignmentSegment(messageId);
    reportDetails(details);
    final uid = _uid();
    (await _access(uid, groupId)).requireWritable();
    final target = _messages(groupId).doc(messageId);
    final own = target.collection('reports').doc(uid);
    await _checked(uid, () => _db.runTransaction((transaction) async {
      final existing = await _checked(uid, () => transaction.get(own));
      _document(existing, own.path);
      final message = await _checked(uid, () => transaction.get(target));
      _document(message, target.path);
      if (existing.exists) throw const FormatException('You have already reported this message.');
      if (!message.exists) throw const FormatException('Message unavailable. Refresh history.');
      FirebaseChatMessage.parse(groupId, messageId, message.data());
      _same(uid);
      transaction.set(own, {
        'reporterUid': uid, 'reason': reason.name, 'details': details,
        'createdAt': FieldValue.serverTimestamp(), 'status': 'open',
        'resolvedBy': null, 'resolvedAt': null
      });
    }));
  }
}