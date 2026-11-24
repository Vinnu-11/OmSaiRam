import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../firebase_assignments/data/firebase_assignment_models.dart';
import '../../firebase_groups/data/firebase_group_models.dart';

typedef FirebaseMemberDisplayBinding = ({String uid, String groupId});

String memberDisplayName(String value) {
  if (value.isEmpty || value.length > 100 || value.trim().isEmpty) {
    throw const FormatException('Enter a nonblank name of 1–100 characters.');
  }
  return value;
}

int memberDisplayIdCompare(String a, String b) {
  final left = utf8.encode(a), right = utf8.encode(b);
  for (var i = 0; i < left.length && i < right.length; i++) {
    if (left[i] != right[i]) return left[i].compareTo(right[i]);
  }
  return left.length.compareTo(right.length);
}

/// Group-visible, opt-in, unverified text. Never a permission/identity source.
class FirebaseMemberDisplay {
  final String groupId, uid, displayName;
  final Timestamp createdAt, updatedAt;
  FirebaseMemberDisplay.parse(this.groupId, this.uid, Map<String, dynamic>? raw)
      : displayName = memberDisplayName(textField(exactData(raw,
          {'displayName', 'createdAt', 'updatedAt'}), 'displayName', 100)),
        createdAt = _timestamp(raw!, 'createdAt'),
        updatedAt = _timestamp(raw, 'updatedAt') {
    assignmentSegment(groupId);
    assignmentSegment(uid);
  }
  static Timestamp _timestamp(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value is! Timestamp) throw FormatException('Invalid server $key.');
    return value; // Keep exact nanoseconds; never roundtrip through DateTime.
  }
}

class FirebaseMemberDisplayPage {
  final FirebaseMemberDisplayBinding binding;
  final List<FirebaseMemberDisplay> names;
  final FirebaseMemberDisplay? own;
  final int pageSize;
  final String? after;
    final bool archived;
  FirebaseMemberDisplayPage(this.binding, Iterable<FirebaseMemberDisplay> names,
      {this.own, this.pageSize = 20, this.after, this.archived = false}) : names = List.unmodifiable(names) {
    assignmentSegment(binding.uid); assignmentSegment(binding.groupId);
    boundedPageSize(pageSize);
    if (after != null) assignmentSegment(after!);
    if (this.names.length > pageSize) throw const FormatException('Oversized names page.');
    var previous = after;
    for (final name in this.names) {
      if (name.groupId != binding.groupId ||
          (previous != null && memberDisplayIdCompare(previous, name.uid) >= 0)) {
        throw const FormatException('Invalid names page scope or order.');
      }
      previous = name.uid;
    }
    if (own != null && (own!.uid != binding.uid || own!.groupId != binding.groupId)) {
      throw const FormatException('Invalid own published name scope.');
    }
  }
  String? get cursor => names.isEmpty ? null : names.last.uid;
  bool get hasMore => names.length == pageSize;
}

const memberDisplayDisclosure =
    'Publishing is optional. This name is visible to current group members, '
    'is unverified and not unique, and may differ from your private name. '
    'UIDs remain the identity and permission references. You can publish or change '
    'a name, but cannot unpublish it yet. It is retained until departure cleanup; '
    'this is not privacy erasure and cannot erase names already downloaded.';