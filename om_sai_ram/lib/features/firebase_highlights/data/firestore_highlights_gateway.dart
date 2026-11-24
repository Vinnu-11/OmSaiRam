import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../firebase_auth/data/firebase_auth_repository.dart';
import '../../firebase_assignments/data/firebase_assignment_models.dart';
import '../../firebase_groups/data/firebase_group_models.dart';
import 'firebase_highlight_models.dart';

abstract class FirebaseHighlightsGateway {
  Future<FirebaseHighlightsPage> read(String groupId,
      {int pageSize = 20, FirebaseHighlightCursor? after});
  /// Completion acknowledges only the write, not a subsequent head read.
  Future<void> send(String groupId, FirebaseHighlightDraft draft);
  Future<void> report(String groupId, String highlightId,
      FirebaseHighlightReportReason reason, String details);
}
final firebaseHighlightsGatewayProvider = Provider<FirebaseHighlightsGateway>((ref) {
  throw StateError('Firebase highlights bootstrap has not completed.');
});

/// Uses only the injected named-app SDK pair. No caller-supplied identity.
class FirestoreHighlightsGateway implements FirebaseHighlightsGateway {
  final FirebaseAuth _auth;
  final FirebaseFirestore _db;
  FirestoreHighlightsGateway(this._auth, this._db);
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
    } catch (_) { _same(uid); rethrow; }
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
  Future<DocumentSnapshot<Map<String, dynamic>>> _get(String uid,
      DocumentReference<Map<String, dynamic>> doc) async {
    final snapshot = await _checked(uid, () => doc.get(_server));
    _same(uid);
    _document(snapshot, doc.path);
    return snapshot;
  }
  Future<FirebaseGroup> _access(String uid, String groupId) async {
    final profile = await _get(uid, _db.collection('users').doc(uid));
    _same(uid);
    final data = exactData(profile.data(), {'displayName', 'createdAt', 'updatedAt'});
    validateDisplayName(textField(data, 'displayName', 100));
    if (data['createdAt'] is! Timestamp || data['updatedAt'] is! Timestamp) {
      throw const FormatException('Confirmed private profile timestamps required.');
    }
    final group = _db.collection('groups').doc(groupId);
    final groupSnapshot = await _get(uid, group);
    _same(uid);
    final parsedGroup = FirebaseGroup.parse(groupId, groupSnapshot.data());
    final member = await _get(uid, group.collection('members').doc(uid));
    _same(uid);
    FirebaseMembership.parse(uid, member.data());
    return parsedGroup;
  }
  CollectionReference<Map<String, dynamic>> _highlights(String groupId) =>
      _db.collection('groups').doc(groupId).collection('highlights');
  @override
  Future<FirebaseHighlightsPage> read(String groupId,
      {int pageSize = 20, FirebaseHighlightCursor? after}) async {
    assignmentSegment(groupId);
    boundedPageSize(pageSize);
    if (after != null) assignmentSegment(after.id);
    final uid = _uid();
    final parsedGroup = await _checked(uid, () => _access(uid, groupId));
    _same(uid);
    Query<Map<String, dynamic>> query = _highlights(groupId)
      .orderBy('createdAt', descending: true)
      .orderBy(FieldPath.documentId, descending: true).limit(pageSize);
    if (after != null) query = query.startAfter([after.createdAt, after.id]);
    final snapshot = await _checked(uid, () => query.get(_server));
    _same(uid);
    _confirmed(snapshot.metadata);
    final rows = snapshot.docs.map((doc) {
      assignmentSegment(doc.id);
      _document(doc, '${_highlights(groupId).path}/${doc.id}');
      return FirebaseHighlight.parse(groupId, doc.id, doc.data());
    });
    final page = FirebaseHighlightsPage(uid, groupId, rows, archived: parsedGroup.archived);
    page.validate((uid: uid, groupId: groupId), pageSize, after);
    _same(uid);
    return page;
  }
  @override
  Future<void> send(String groupId, FirebaseHighlightDraft draft) async {
    assignmentSegment(groupId);
    final uid = _uid();
    (await _checked(uid, () => _access(uid, groupId))).requireWritable();
    _same(uid);
    final doc = _highlights(groupId).doc();
    // One auto-ID attempt only. No optimistic entry, queue or background retry.
    try {
      await _checked(uid, () => doc.set({
        'senderUid': uid, 'chapterNumber': draft.chapterNumber,
        'paragraphIndex': draft.paragraphIndex, 'quote': draft.quote, 'text': draft.text,
        'createdAt': FieldValue.serverTimestamp()
      }));
      _same(uid);
    } catch (_) {
      _same(uid);
      throw const FirebaseHighlightDeliveryUncertain();
    }
  }
  @override
  Future<void> report(String groupId, String highlightId,
      FirebaseHighlightReportReason reason, String details) async {
    assignmentSegment(groupId);
    assignmentSegment(highlightId);
    highlightReportDetails(details);
    final uid = _uid();
    (await _checked(uid, () => _access(uid, groupId))).requireWritable();
    _same(uid);
    final target = _highlights(groupId).doc(highlightId);
    final own = target.collection('reports').doc(uid);
    await _checked(uid, () => _db.runTransaction((transaction) async {
      final existing = await _checked(uid, () => transaction.get(own));
      _same(uid);
      _document(existing, own.path);
      final highlight = await _checked(uid, () => transaction.get(target));
      _same(uid);
      _document(highlight, target.path);
      if (existing.exists) throw const FormatException('You have already reported this highlight.');
      if (!highlight.exists) throw const FormatException('Highlight unavailable. Refresh newest highlights.');
      FirebaseHighlight.parse(groupId, highlightId, highlight.data());
      _same(uid);
      transaction.set(own, {
        'reporterUid': uid, 'reason': reason.name, 'details': details,
        'createdAt': FieldValue.serverTimestamp(), 'status': 'open',
        'resolvedBy': null, 'resolvedAt': null
      });
    }));
    _same(uid);
  }
}