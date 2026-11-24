import 'package:cloud_firestore/cloud_firestore.dart';

String documentId(String value) {
  if (value.isEmpty || value.contains('/') || value == '.' || value == '..') {
    throw const FormatException('Invalid document ID.');
  }
  return value;
}

int boundedPageSize(int size) {
  if (size < 1 || size > 50) {
    throw const FormatException('Page size must be 1–50.');
  }
  return size;
}

/// Capital letters and digits without the look-alikes I, O, 0 and 1.
const inviteCodeAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

String inviteToken(String value) {
  if (!RegExp(r'^([a-f0-9]{64}|[A-HJ-NP-Z2-9]{8})$').hasMatch(value)) {
    throw const FormatException('Enter the 8-letter invite code.');
  }
  return value;
}

/// Finds an invite in what a person typed or pasted: the code itself (any case,
/// with spaces or a dash), a join link, or a whole shared message.
String inviteFromText(String text) {
  final link = RegExp(r'[?&]code=([A-Za-z0-9-]+)').firstMatch(text);
  final dashed = RegExp(r'\b([A-Za-z2-9]{4})-([A-Za-z2-9]{4})\b').allMatches(text);
  final hex = RegExp(r'\b[a-f0-9]{64}\b').firstMatch(text);
  final candidates = [
    if (link != null) link[1]!.replaceAll('-', ''),
    for (final match in dashed) '${match[1]}${match[2]}',
    if (hex != null) hex[0]!,
    text.replaceAll(RegExp(r'[\s-]'), ''),
  ];
  for (final candidate in candidates) {
    final value = candidate.length == 8 ? candidate.toUpperCase() : candidate;
    try {
      return inviteToken(value);
    } on FormatException {
      continue;
    }
  }
  throw const FormatException('Enter the 8-letter invite code.');
}

/// "ABCD-EFGH" for 8-letter codes; older long tokens are shown unchanged.
String displayInvite(String token) =>
    token.length == 8 ? '${token.substring(0, 4)}-${token.substring(4)}' : token;

Map<String, dynamic> exactData(Map<String, dynamic>? data,
    Set<String> required, [Set<String> optional = const {}]) {
  if (data == null || !data.keys.toSet().containsAll(required) ||
      !required.union(optional).containsAll(data.keys)) {
    throw const FormatException('Invalid server document fields.');
  }
  return data;
}

String textField(Map<String, dynamic> data, String key, int max,
    {bool nonempty = true}) {
  final value = data[key];
  if (value is! String || value.length > max ||
      (nonempty && value.trim().isEmpty)) {
    throw FormatException('Invalid server $key.');
  }
  return value;
}

int intField(Map<String, dynamic> data, String key, int min, int max) {
  final value = data[key];
  if (value is! int || value < min || value > max) {
    throw FormatException('Invalid server $key.');
  }
  return value;
}

DateTime dateField(Map<String, dynamic> data, String key) {
  final value = data[key];
  if (value is! Timestamp) throw FormatException('Invalid server $key.');
  return value.toDate().toUtc();
}

class FirebaseGroup {
  final String id, name, description, mode, createdBy;
  final String ownerUid;
  final int ownershipRevision;
  final int chaptersPerWeek, startChapter, currentWeek;
  final DateTime createdAt, updatedAt;
  final bool archived;
  final int lifecycleRevision;
  final String? lifecycleChangedBy;
  final DateTime? lifecycleChangedAt;
  const FirebaseGroup({required this.id, required this.name,
    required this.description, required this.mode, required this.createdBy,
    required this.chaptersPerWeek, required this.startChapter,
    required this.currentWeek, required this.createdAt, required this.updatedAt,
    this.archived = false, this.lifecycleRevision = 0,
    this.lifecycleChangedBy, this.lifecycleChangedAt, String? ownerUid,
    this.ownershipRevision = 0}) : ownerUid = ownerUid ?? createdBy;

  void requireWritable() {
    if (archived) throw const FormatException('This group is archived and read-only. An admin must restore it first.');
  }

  factory FirebaseGroup.parse(String id, Map<String, dynamic>? raw) {
    const lifecycle = {'archived', 'lifecycleRevision', 'lifecycleChangedBy', 'lifecycleChangedAt'};
    const ownership = {'ownerUid', 'ownershipRevision', 'ownershipChangedBy', 'ownershipChangedAt'};
    final data = exactData(raw, {'name', 'description', 'mode', 'createdBy',
      'chaptersPerWeek', 'startChapter', 'currentWeek', 'createdAt', 'updatedAt'}, lifecycle.union(ownership));
    final hasOwnership = data.keys.any(ownership.contains);
    if (hasOwnership) {
      if (!data.keys.toSet().containsAll(ownership)) throw const FormatException('Invalid group ownership fields.');
      documentId(textField(data, 'ownerUid', 128));
      intField(data, 'ownershipRevision', 1, 2147483647);
      documentId(textField(data, 'ownershipChangedBy', 128));
      dateField(data, 'ownershipChangedAt'); dateField(data, 'updatedAt');
      if ((data['ownershipChangedAt'] as Timestamp).compareTo(data['updatedAt'] as Timestamp) > 0) {
        throw const FormatException('Invalid ownership audit time.');
      }
    }
    final hasLifecycle = data.keys.any(lifecycle.contains);
    if (hasLifecycle && (!data.keys.toSet().containsAll(lifecycle) || data['archived'] is! bool)) {
      throw const FormatException('Invalid server group lifecycle.');
    }
    final updatedAt = dateField(data, 'updatedAt');
    final changedAt = hasLifecycle ? dateField(data, 'lifecycleChangedAt') : null;
    if (hasLifecycle && (data['lifecycleChangedAt'] as Timestamp).compareTo(data['updatedAt'] as Timestamp) > 0) {
      throw const FormatException('Invalid server group lifecycle time.');
    }
    final mode = data['mode'];
    if (mode != 'chapter_wise' && mode != 'saptah') {
      throw const FormatException('Invalid server group mode.');
    }
    return FirebaseGroup(id: documentId(id),
      name: textField(data, 'name', 100),
      description: textField(data, 'description', 1000, nonempty: false),
      mode: mode as String, createdBy: documentId(textField(data, 'createdBy', 128)),
      chaptersPerWeek: intField(data, 'chaptersPerWeek', 1, 53),
      startChapter: intField(data, 'startChapter', 1, 53),
      currentWeek: intField(data, 'currentWeek', 1, 10000),
      createdAt: dateField(data, 'createdAt'), updatedAt: updatedAt,
      archived: hasLifecycle ? data['archived'] as bool : false,
      lifecycleRevision: hasLifecycle ? intField(data, 'lifecycleRevision', 1, 2147483647) : 0,
      lifecycleChangedBy: hasLifecycle ? documentId(textField(data, 'lifecycleChangedBy', 1500)) : null,
      lifecycleChangedAt: changedAt,
      ownerUid: hasOwnership ? data['ownerUid'] as String : null,
      ownershipRevision: hasOwnership ? data['ownershipRevision'] as int : 0);
  }
}

enum FirebaseGroupRole { admin, groupLead, member }

/// Admins and group leads may invite people and move the group to the next week.
bool isGroupLeader(FirebaseGroupRole role) =>
    role == FirebaseGroupRole.admin || role == FirebaseGroupRole.groupLead;

class FirebaseMembership {
  final String uid;
  final FirebaseGroupRole role;
  final DateTime joinedAt;
  final Timestamp? joinedAtToken;
  const FirebaseMembership(this.uid, this.role, this.joinedAt, {this.joinedAtToken});
  factory FirebaseMembership.parse(String uid, Map<String, dynamic>? raw) {
    final data = exactData(raw, {'userId', 'role', 'joinedAt'});
    if (data['userId'] != documentId(uid)) {
      throw const FormatException('Membership UID mismatch.');
    }
    final role = switch (data['role']) {
      'admin' => FirebaseGroupRole.admin,
      'group_lead' => FirebaseGroupRole.groupLead,
      'member' => FirebaseGroupRole.member,
      _ => throw const FormatException('Invalid server membership role.'),
    };
    return FirebaseMembership(uid, role, dateField(data, 'joinedAt'), joinedAtToken: data['joinedAt'] as Timestamp);
  }
  String get roleLabel => switch (role) {
    FirebaseGroupRole.admin => 'admin',
    FirebaseGroupRole.groupLead => 'group_lead',
    FirebaseGroupRole.member => 'member',
  };
}

class FirebaseGroupIndex {
  final String groupId;
  final DateTime joinedAt;
  const FirebaseGroupIndex(this.groupId, this.joinedAt);
  factory FirebaseGroupIndex.parse(String id, Map<String, dynamic>? raw) {
    final data = exactData(raw, {'groupId', 'joinedAt'}, {'inviteToken'});
    if (data['groupId'] != documentId(id)) {
      throw const FormatException('Group index ID mismatch.');
    }
    if (data.containsKey('inviteToken')) {
      final token = data['inviteToken'];
      if (token is! String) throw const FormatException('Invalid index token.');
      inviteToken(token);
    }
    return FirebaseGroupIndex(id, dateField(data, 'joinedAt'));
  }
}

/// The cursor is the last INDEX/member document ID, not a hydrated item ID.
/// A full page may be followed by an empty page. Always preserve its cursor.
class FirebasePage<T> {
  final List<T> items;
  final String? cursor;
  final bool hasMore;
  FirebasePage(Iterable<T> items, {this.cursor, required this.hasMore})
      : items = List.unmodifiable(items) {
    if (cursor != null) documentId(cursor!);
    if (hasMore && cursor == null) {
      throw const FormatException('Continuation requires a cursor.');
    }
  }
}

class FirebaseGroupEntry {
  final FirebaseGroup group;
  final FirebaseMembership self;
  const FirebaseGroupEntry(this.group, this.self);
}

class FirebaseGroupDetail {
  final FirebaseGroup group;
  final FirebaseMembership self;
  final FirebasePage<FirebaseMembership> members;
  const FirebaseGroupDetail(this.group, this.self, this.members);
}

class FirebaseGroupDraft {
  final String name, description;
  final int chaptersPerWeek, startChapter;
  /// 'saptah' is a label only; it is scheduled weekly like 'chapter_wise'.
  final String mode;
  FirebaseGroupDraft(String name, String description,
      {this.chaptersPerWeek = 2, this.startChapter = 1, this.mode = 'chapter_wise'})
      : name = name.trim(), description = description.trim() {
    if (this.name.isEmpty || this.name.length > 100 ||
        (mode != 'chapter_wise' && mode != 'saptah') ||
        this.description.length > 1000 || chaptersPerWeek < 1 ||
        chaptersPerWeek > 48 || startChapter < 1 || startChapter > 53) {
      throw const FormatException(
          'Name: 1–100 characters; description: up to 1000; width: 1–48; start: 1–53.');
    }
  }
}

class FirebaseGroupInvite {
  final String token, groupId, createdBy;
  final DateTime createdAt, expiresAt;
  final bool active;
  const FirebaseGroupInvite(this.token, this.groupId, this.createdBy,
      this.createdAt, this.expiresAt, this.active);
  factory FirebaseGroupInvite.parse(String token, Map<String, dynamic>? raw) {
    inviteToken(token);
    final data = exactData(raw,
        {'groupId', 'createdBy', 'createdAt', 'expiresAt', 'active'});
    if (data['active'] is! bool) {
      throw const FormatException('Invalid server invite active flag.');
    }
    final created = dateField(data, 'createdAt');
    final expires = dateField(data, 'expiresAt');
    if (!expires.isAfter(created) || expires.difference(created) > const Duration(days: 7)) {
      throw const FormatException('Invalid server invite expiration.');
    }
    return FirebaseGroupInvite(token, documentId(textField(data, 'groupId', 1500)),
      documentId(textField(data, 'createdBy', 128)), created, expires, data['active'] as bool);
  }
  void requireUsable(DateTime now) {
    if (!active || !expiresAt.isAfter(now.toUtc())) {
      throw const FormatException('This invite is expired or revoked.');
    }
  }
}