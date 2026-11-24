import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../firebase_auth/data/firebase_auth_repository.dart';
import 'firebase_group_models.dart';

abstract class FirebaseGroupsGateway {
  Future<FirebasePage<FirebaseGroupEntry>> listGroups({int pageSize = 20, String? cursor});
  Future<FirebaseGroupDetail> detail(String groupId, {int pageSize = 20, String? cursor});
  Future<String> create(FirebaseGroupDraft draft);
  Future<String> join(String token);
  Future<FirebaseGroupInvite> issueInvite(String groupId, {Duration lifetime = const Duration(hours: 24)});
  Future<void> revokeInvite(String token);
}

final firebaseGroupsGatewayProvider = Provider<FirebaseGroupsGateway>((ref) {
  throw StateError('Firebase emulator groups bootstrap has not completed.');
});

/// Only the configured named app SDK instances are injected. No caller UID.
class FirestoreGroupsGateway implements FirebaseGroupsGateway {
  final FirebaseAuth _auth;
  final FirebaseFirestore _db;
  FirestoreGroupsGateway(this._auth, this._db);
  static const _server = GetOptions(source: Source.server);

  String _uid() {
    final uid = _auth.currentUser?.uid;
    if (uid == null || uid.isEmpty) throw StateError('Sign in to Firebase first.');
    return uid;
  }

  void _sameUser(String uid) {
    if (_uid() != uid) throw StateError('Firebase account changed. Retry.');
  }

  Future<String> _ready() async {
    final uid = _uid();
    final snapshot = await _db.collection('users').doc(uid).get(_server);
    _serverSnapshot(snapshot);
    final data = exactData(snapshot.data(), {'displayName', 'createdAt', 'updatedAt'});
    validateDisplayName(textField(data, 'displayName', 100));
    dateField(data, 'createdAt');
    dateField(data, 'updatedAt');
    _sameUser(uid);
    return uid;
  }

  void _serverSnapshot(DocumentSnapshot snapshot) {
    if (snapshot.metadata.isFromCache || snapshot.metadata.hasPendingWrites) {
      throw StateError('Confirmed server data required. Retry when online.');
    }
  }

  Query<Map<String, dynamic>> _page(CollectionReference<Map<String, dynamic>> collection,
      int size, String? cursor) {
    var query = collection.orderBy(FieldPath.documentId).limit(boundedPageSize(size));
    if (cursor != null) query = query.startAfter([documentId(cursor)]);
    return query;
  }

  Future<FirebaseGroupEntry> _entry(String groupId, String uid) async {
    documentId(groupId);
    _sameUser(uid);
    final group = await _db.collection('groups').doc(groupId).get(_server);
    _serverSnapshot(group);
    _sameUser(uid);
    final self = await group.reference.collection('members').doc(uid).get(_server);
    _serverSnapshot(self);
    _sameUser(uid);
    return FirebaseGroupEntry(FirebaseGroup.parse(groupId, group.data()),
        FirebaseMembership.parse(uid, self.data()));
  }

  @override
  Future<FirebasePage<FirebaseGroupEntry>> listGroups({int pageSize = 20, String? cursor}) async {
    boundedPageSize(pageSize);
    if (cursor != null) documentId(cursor);
    final uid = await _ready();
    final result = await _page(_db.collection('users').doc(uid).collection('groups'),
        pageSize, cursor).get(_server);
    if (result.metadata.isFromCache || result.metadata.hasPendingWrites) {
      throw StateError('Confirmed server index required.');
    }
    final entries = <FirebaseGroupEntry>[];
    // Fail the ENTIRE page on stale/denied/malformed index or group; never skip.
    for (final doc in result.docs) {
      _serverSnapshot(doc);
      final index = FirebaseGroupIndex.parse(doc.id, doc.data());
      entries.add(await _entry(index.groupId, uid));
    }
    _sameUser(uid);
    return FirebasePage(entries, cursor: result.docs.isEmpty ? cursor : result.docs.last.id,
        hasMore: result.docs.length == pageSize);
  }

  @override
  Future<FirebaseGroupDetail> detail(String groupId, {int pageSize = 20, String? cursor}) async {
    documentId(groupId);
    boundedPageSize(pageSize);
    if (cursor != null) documentId(cursor);
    final uid = await _ready();
    final entry = await _entry(groupId, uid);
    final result = await _page(_db.collection('groups').doc(groupId).collection('members'),
        pageSize, cursor).get(_server);
    if (result.metadata.isFromCache || result.metadata.hasPendingWrites) {
      throw StateError('Confirmed server roster required.');
    }
    final members = result.docs.map((doc) {
      _serverSnapshot(doc);
      return FirebaseMembership.parse(doc.id, doc.data());
    }).toList();
    _sameUser(uid);
    return FirebaseGroupDetail(entry.group, entry.self,
      FirebasePage(members, cursor: result.docs.isEmpty ? cursor : result.docs.last.id,
        hasMore: result.docs.length == pageSize));
  }

  @override
  Future<String> create(FirebaseGroupDraft draft) async {
    final uid = await _ready();
    final group = _db.collection('groups').doc();
    final batch = _db.batch();
    final time = FieldValue.serverTimestamp();
    batch.set(group, {'name': draft.name, 'description': draft.description,
      'mode': draft.mode, 'chaptersPerWeek': draft.chaptersPerWeek,
      'startChapter': draft.startChapter, 'currentWeek': 1, 'createdBy': uid,
      'createdAt': time, 'updatedAt': time});
    batch.set(group.collection('members').doc(uid),
      {'userId': uid, 'role': 'admin', 'joinedAt': time});
    batch.set(_db.collection('users').doc(uid).collection('groups').doc(group.id),
      {'groupId': group.id, 'joinedAt': time});
    _sameUser(uid);
    await batch.commit();
    _sameUser(uid);
    return group.id;
  }

  @override
  Future<String> join(String token) async {
    inviteToken(token);
    final uid = await _ready();
    final snapshot = await _db.collection('groupInvites').doc(token).get(_server);
    _serverSnapshot(snapshot);
    final invite = FirebaseGroupInvite.parse(token, snapshot.data());
    invite.requireUsable(DateTime.now()); // UX only; rules time is authoritative.
    _sameUser(uid);
    // No group read before joining. Existing member/index updates are denied by
    // rules, so repeated joins fail atomically, never reset role/joinedAt.
    final batch = _db.batch();
    final time = FieldValue.serverTimestamp();
    batch.set(_db.collection('groups').doc(invite.groupId).collection('members').doc(uid),
      {'userId': uid, 'role': 'member', 'joinedAt': time});
    batch.set(_db.collection('users').doc(uid).collection('groups').doc(invite.groupId),
      {'groupId': invite.groupId, 'joinedAt': time, 'inviteToken': token});
    _sameUser(uid);
    await batch.commit();
    _sameUser(uid);
    return invite.groupId;
  }

  Future<FirebaseMembership> _inviter(String groupId, String uid) async {
    final entry = await _entry(groupId, uid);
    entry.group.requireWritable();
    if (!isGroupLeader(entry.self.role)) {
      throw const FormatException('Only the group admin or a group lead can invite.');
    }
    return entry.self;
  }

  @override
  Future<FirebaseGroupInvite> issueInvite(String groupId,
      {Duration lifetime = const Duration(hours: 24)}) async {
    documentId(groupId);
    if (lifetime <= Duration.zero || lifetime > const Duration(days: 7)) {
      throw const FormatException('Invite lifetime must be positive and at most seven days.');
    }
    final uid = await _ready();
    await _inviter(groupId, uid);
    final random = Random.secure(); // Failure propagates: no weak fallback.
    final token = List.generate(8, (_) => inviteCodeAlphabet[random.nextInt(32)]).join();
    final expires = DateTime.now().toUtc().add(lifetime);
    final doc = _db.collection('groupInvites').doc(token);
    await _db.runTransaction((transaction) async {
      _sameUser(uid);
      final existing = await transaction.get(doc);
      if (existing.exists) throw StateError('Invite collision. Retry issuance.');
      _sameUser(uid);
      transaction.set(doc, {'groupId': groupId, 'createdBy': uid,
        'createdAt': FieldValue.serverTimestamp(),
        'expiresAt': Timestamp.fromDate(expires), 'active': true});
    });
    _sameUser(uid);
    final saved = await doc.get(_server);
    _serverSnapshot(saved);
    _sameUser(uid);
    return FirebaseGroupInvite.parse(token, saved.data());
  }

  @override
  Future<void> revokeInvite(String token) async {
    inviteToken(token);
    final uid = await _ready();
    final doc = _db.collection('groupInvites').doc(token);
    final snapshot = await doc.get(_server);
    _serverSnapshot(snapshot);
    final invite = FirebaseGroupInvite.parse(token, snapshot.data());
    final self = await _inviter(invite.groupId, uid);
    if (self.role != FirebaseGroupRole.admin && invite.createdBy != uid) {
      throw const FormatException('Only the person who made this invite or the admin can cancel it.');
    }
    _sameUser(uid);
    await doc.update({'active': false});
    _sameUser(uid);
  }
}