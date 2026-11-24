import 'dart:convert';
import '../../../core/providers/language_provider.dart';
import 'firebase_assignment_models.dart';

class FirebaseAssignmentResume {
  final FirebaseAssignmentsScope scope;
  final String unitKey, language;
  final double position;
  FirebaseAssignmentResume(
      {required this.scope,
      required this.unitKey,
      required this.language,
      required this.position}) {
    validateAssignmentsScope(scope);
    if (!FirebaseChapterUnit.all.any((unit) => unit.key == unitKey) ||
        !AppLanguage.values.any((item) => item.code == language) ||
        !position.isFinite ||
        position < 0 ||
        position > 1) {
      throw const FormatException('Invalid saved assignment position.');
    }
  }
  bool matches(FirebaseAssignmentsScope current, String unit,
          String requestedLanguage) =>
      scope == current && unitKey == unit && language == requestedLanguage;
  String get location =>
      '/groups/${Uri.encodeComponent(scope.groupId)}/assignments/read/'
      '${Uri.encodeComponent(scope.memberUid)}/${scope.week}/${Uri.encodeComponent(unitKey)}';
  String encode() => jsonEncode({
        'version': 1,
        'uid': scope.uid,
        'groupId': scope.groupId,
        'memberUid': scope.memberUid,
        'week': scope.week,
        'unitKey': unitKey,
        'language': language,
        'position': position
      });
  factory FirebaseAssignmentResume.decode(String value, String uid) {
    final data = jsonDecode(value);
    const fields = {
      'version',
      'uid',
      'groupId',
      'memberUid',
      'week',
      'unitKey',
      'language',
      'position'
    };
    if (data is! Map<String, dynamic> ||
        data.length != fields.length ||
        !data.keys.toSet().containsAll(fields) ||
        data['version'] is! int ||
        data['version'] != 1 ||
        data['uid'] != uid ||
        data['groupId'] is! String ||
        data['memberUid'] is! String ||
        data['week'] is! int ||
        data['unitKey'] is! String ||
        data['language'] is! String ||
        data['position'] is! num) {
      throw const FormatException('Invalid saved assignment fields.');
    }
    return FirebaseAssignmentResume(
        scope: (
          uid: uid,
          groupId: data['groupId'] as String,
          memberUid: data['memberUid'] as String,
          week: data['week'] as int
        ),
        unitKey: data['unitKey'] as String,
        language: data['language'] as String,
        position: (data['position'] as num).toDouble());
  }
}

String firebaseAssignmentResumeKey(String uid) =>
    'firebase_assignment_resume_v1_${Uri.encodeComponent(assignmentSegment(uid))}';
