import 'package:flutter_test/flutter_test.dart';
import 'package:om_sai_ram/features/firebase_assignments/data/firebase_assignment_models.dart';
import 'package:om_sai_ram/features/firebase_scheduling/data/firebase_schedule_models.dart';

FirebaseScheduleSettings settings({int width = 2, int start = 1, int week = 7, String mode = 'chapter_wise'}) =>
  FirebaseScheduleSettings(mode: mode, chaptersPerWeek: width, startChapter: start, currentWeek: week);
FirebaseSchedulePlan plan({List<String> members = const ['z', 'a', 'm'], int weeks = 2,
  String mode = 'independent', String remainder = 'manual', int? start, DateTime? date}) =>
  FirebaseSchedulePlan(memberUids: members, weeksAhead: weeks, scheduleMode: mode,
    remainderMode: remainder, startChapter: start, firstWeekDate: date);

void main() {
  const h0 = FirebaseScheduleHint(position: 0, chapterStart: 1);
  test('suggestion JS nonadjacent golden inner chapters infer position-zero canonical base', () {
    final result = suggestFirebaseSchedule(settings(), plan(members: ['a','b','c','d']), const [
      FirebaseScheduleHint(position: 3, chapterStart: 23), FirebaseScheduleHint(position: 1, chapterStart: 19)]);
    expect(result.detectedMode, 'rotating_window'); expect(result.detectedStep, 2);
    expect(result.plan.startChapter, 15);
    expect(result.preview.assignments.take(8).map((r) => r.unit.key), ['15','16-17','18-19','20','21','22','23','24']);
  });
  for (final width in [1,2,48]) {
    for (final step in {0,1,width}) {
      test('suggestion mode priority width $width step $step', () {
        // Width 48 cannot have two distinct in-book starts separated by 48.
        if (step == 48) {
          expect(() => suggestFirebaseSchedule(settings(width: width), plan(), const [h0,
            FirebaseScheduleHint(position: 1, chapterStart: 53)]), throwsFormatException);
          return;
        }
        final input = plan(members: ['a','b','c','d']);
        final result = suggestFirebaseSchedule(settings(width: width), input, [3,0,2].map((p) =>
          FirebaseScheduleHint(position: p, chapterStart: FirebaseChapterUnit.all[4+p*step].start)));
        expect(result.detectedMode, step == 0 ? 'synchronized' : step == width ? 'rotating_window' : 'dense_window');
        expect(result.detectedStep, step); expect(result.plan.startChapter, 5);
        expect(input.scheduleMode, 'independent'); expect(input.startChapter, isNull);
      });
    }
  }
  final invalidHints = <List<FirebaseScheduleHint>>[
    [], [h0], [h0,h0,h0,h0,h0],
    [h0,const FirebaseScheduleHint(position: 1, chapterStart: 3),const FirebaseScheduleHint(position: 3, chapterStart: 8)],
    [const FirebaseScheduleHint(position: 1, chapterStart: 2),const FirebaseScheduleHint(position: 1, chapterStart: 2)],
    [h0,const FirebaseScheduleHint(position: 1, chapterStart: 4)],
    [const FirebaseScheduleHint(position: 0, chapterStart: 4),const FirebaseScheduleHint(position: 1, chapterStart: 1)],
    [h0,const FirebaseScheduleHint(position: 2, chapterStart: 2)],
    [const FirebaseScheduleHint(position: 2, chapterStart: 1),const FirebaseScheduleHint(position: 3, chapterStart: 3)],
    for (final position in [-1,4]) [h0,FirebaseScheduleHint(position: position, chapterStart: 2)],
    for (final chapter in [0,54]) [h0,FirebaseScheduleHint(position: 1, chapterStart: chapter)],
  ];
  for (var i = 0; i < invalidHints.length; i++) {
    test('suggestion rejects JS malformed/inconsistent pattern $i', () {
      expect(() => suggestFirebaseSchedule(settings(), plan(members: ['a','b','c','d']), invalidHints[i]), throwsFormatException);
    });
  }
  for (final value in <Map<String,Object?>>[
    {}, {'position':0}, {'position':0,'chapterStart':1,'extra':true},
    {'position':0.5,'chapterStart':1}, {'position':'0','chapterStart':1},
    {'position':0,'chapterStart':1.0}, {'position':null,'chapterStart':1},
    {'position':0,'chapterStart':'1'},
  ]) {
    test('hint exact map parser rejects $value', () {
      expect(() => FirebaseScheduleHint.parse(value), throwsFormatException);
    });
  }
  test('hint parser copies integer values without retaining mutable map', () {
    final raw = <String,Object?>{'position':1,'chapterStart':17};
    final hint = FirebaseScheduleHint.parse(raw); raw['position'] = 9;
    expect(hint.position, 1); expect(hint.chapterStart, 17);
  });
  test('invalid bounded preview is rejected before hint traversal', () {
    Iterable<FirebaseScheduleHint> poisoned() sync* { throw StateError('Traversed hints'); }
    for (final input in [plan(weeks:13),plan(remainder:'unknown'),plan(mode:'custom'),plan(start:54),
      plan(mode:'synchronized',remainder:'extend_last'),
      plan(members:List.generate(50,(i)=>'u$i'),weeks:12)]) {
      expect(() => suggestFirebaseSchedule(settings(width:48), input, poisoned()), throwsFormatException);
    }
    expect(() => suggestFirebaseSchedule(settings(mode:'other'), plan(), poisoned()), throwsFormatException);
  });
  for (final remainder in FirebaseSchedulePlan.finishingRemainders) {
    test('hint suggestions never infer independent, so $remainder is refused', () {
      expect(() => suggestFirebaseSchedule(settings(), plan(remainder: remainder), const [h0,
        FirebaseScheduleHint(position: 1, chapterStart: 3)]), throwsFormatException);
    });
  }
  for (final remainder in ['manual', 'truncate', 'cycle']) {
    test('suggestion preserves immutable order/weeks/date/remainder and $remainder overflow', () {
      final members = ['b','a'], hints = [const FirebaseScheduleHint(position:1,chapterStart:53),
        const FirebaseScheduleHint(position:0,chapterStart:52)];
      final date = DateTime.utc(2026,10,31,18,30);
      final input = plan(members:members,weeks:3,remainder:remainder,date:date);
      final result = suggestFirebaseSchedule(settings(),input,hints);
      hints.clear(); members.clear();
      expect(result.detectedMode,'synchronized'); expect(result.plan.startChapter,51);
      expect(result.plan.memberUids,['b','a']); expect(result.plan.weeksAhead,3);
      expect(result.plan.remainderMode,remainder); expect(result.plan.firstWeekDate,date);
      expect(result.preview.requestedCount,12);
      expect(result.preview.unfilledCount,remainder=='cycle'?0:10);
      expect(result.preview.reviewRequired,remainder=='manual');
      expect(() => result.plan.memberUids.clear(),throwsUnsupportedError);
      expect(() => result.preview.assignments.clear(),throwsUnsupportedError);
      expect(() => result.preview.unfilled.clear(),throwsUnsupportedError);
      if(remainder=='cycle')expect(result.preview.assignments.last.scheduledDate,date.add(const Duration(days:14)));
      expect(input.scheduleMode,'independent'); expect(input.startChapter,isNull);
    });
  }
  test('suggestion maximum members/weeks and exact4096 previews retain atomic gates', () {
    final hints = [h0,const FirebaseScheduleHint(position:1,chapterStart:1)];
    final max = suggestFirebaseSchedule(settings(width:6),plan(members:List.generate(50,(i)=>'u$i'),weeks:12,remainder:'cycle'),hints);
    expect(max.preview.requestedCount,3600); expect(max.preview.commitBlock,isNotNull);
    final exact = suggestFirebaseSchedule(settings(width:32),plan(members:List.generate(32,(i)=>'u$i'),weeks:4,remainder:'cycle'),hints);
    expect(exact.preview.assignments.length,4096); expect(exact.preview.commitBlock,isNotNull);
    final atomic = suggestFirebaseSchedule(settings(width:4),plan(members:List.generate(12,(i)=>'u$i'),weeks:1),hints);
    expect(atomic.preview.assignments.length,48); expect(atomic.preview.commitBlock,isNull);
    final targets = suggestFirebaseSchedule(settings(width:1),plan(members:List.generate(13,(i)=>'u$i'),weeks:1),hints);
    expect(targets.preview.commitBlock,isNotNull);
  });
  test('suggestion date final week and current-week cap validated first', () {
    final hints = [h0,const FirebaseScheduleHint(position:1,chapterStart:1)];
    expect(() => suggestFirebaseSchedule(settings(),plan(date:DateTime.utc(9999,12,31)),hints),throwsFormatException);
    expect(() => suggestFirebaseSchedule(settings(week:10000),plan(),hints),throwsFormatException);
  });
  // Explicit small golden vectors from the reference JS formula (week-major,
  // member-major, slot-major); these are unit POSITIONS, not chapter numbers.
  const goldens = {
    'independent': [1,2,3,4,5,6,7,8,9,10,11,12],
    'rotating_window': [1,2,3,4,5,6,3,4,5,6,7,8],
    'dense_window': [1,2,2,3,3,4,3,4,4,5,5,6],
    'synchronized': [1,2,1,2,1,2,3,4,3,4,3,4],
  };
  for (final mode in FirebaseSchedulePlan.modes) {
    test('$mode golden order and includes current week', () {
      final preview = previewFirebaseSchedule(settings(), plan(mode: mode));
      expect(preview.assignments.map((r) => r.unit.start), goldens[mode]);
      expect(preview.assignments.map((r) => r.userId), ['z','z','a','a','m','m','z','z','a','a','m','m']);
      expect(preview.assignments.map((r) => r.weekNumber), [7,7,7,7,7,7,8,8,8,8,8,8]);
      expect(preview.requestedCount, 12); expect(preview.unfilledCount, 0);
      expect(preview.assignments.every((r) => r.scheduledDate == null), isTrue);
    });
    for (final remainder in FirebaseSchedulePlan.remainders) {
      for (final start in [1, 17, 44, 53]) {
        test('$mode $remainder canonical start $start reference offsets/unfilled', () {
          final finishing = FirebaseSchedulePlan.finishingRemainders.contains(remainder);
          if (finishing && mode != 'independent') {
            expect(() => previewFirebaseSchedule(settings(width: 3, start: start),
              plan(mode: mode, remainder: remainder, weeks: 3)), throwsFormatException);
            return;
          }
          final preview = previewFirebaseSchedule(settings(width: 3, start: start), plan(mode: mode, remainder: remainder, weeks: 3));
          final base = FirebaseChapterUnit.all.indexWhere((u) => u.key == FirebaseChapterUnit.fromChapter(start).key);
          final rows = <String>[], missing = <FirebaseUnfilledSlot>[];
          for (var k = 0; k < 3; k++) {
            for (var i = 0; i < 3; i++) {
              final offsets = {'independent': (3*k+i)*3, 'rotating_window': (k+i)*3,
                'dense_window': 3*k+i, 'synchronized': 3*k};
              for (var slot = 0; slot < 3; slot++) {
                final p = base + offsets[mode]! + slot;
                final uid = ['z','a','m'][i];
                if (p >= 48 && remainder != 'cycle') {
                  missing.add((userId: uid, weekNumber: 7+k, slot: slot, unitPosition: p+1));
                } else { rows.add('$uid/${7+k}/${FirebaseChapterUnit.all[p%48].key}'); }
              }
            }
          }
          // Fewer than one full week (9 units) left after the 27 planned: finish in week 9.
          final extras = 48 - base - 27;
          final finishes = finishing && extras > 0 && extras < 9;
          for (var j = 0; finishes && j < extras; j++) {
            rows.add('${remainder == 'extend_last' ? 'm' : ['z','a','m'][j % 3]}/9/${FirebaseChapterUnit.all[base + 27 + j].key}');
          }
          expect(preview.assignments.map((r) => '${r.userId}/${r.weekNumber}/${r.unit.key}'), rows);
          expect(preview.unfilled, missing); expect(preview.unfilledCount, missing.length);
          expect(preview.extraCount, finishes ? extras : 0);
          expect(preview.requestedCount, 27);
          expect(rows.length + missing.length, 27 + preview.extraCount);
          expect(preview.reviewRequired, remainder == 'manual' && missing.isNotEmpty);
        });
      }
    }
  }
  test('48 originals with combined aliases and no SQL/language IDs', () {
    expect(FirebaseChapterUnit.all.length, 48);
    expect(FirebaseChapterUnit.all.map((u) => u.key).toSet().length, 48);
    for (var i = 1; i <= 53; i++) {
      final unit = FirebaseChapterUnit.fromChapter(i);
      expect(FirebaseChapterUnit.all.any((u) => u.key == unit.key), isTrue);
    }
    expect(FirebaseChapterUnit.fromChapter(17).key, '16-17');
    expect(FirebaseChapterUnit.fromChapter(19).key, '18-19');
    expect(FirebaseChapterUnit.fromChapter(44).key, '43-44');
    for (final number in [51,52,53]) { expect(FirebaseChapterUnit.fromChapter(number).key, '51-53'); }
    final preview = previewFirebaseSchedule(settings(start: 1, width: 48), plan(members: ['z'], weeks: 1));
    expect(preview.assignments.map((r) => r.unit.key), FirebaseChapterUnit.all.map((u) => u.key));
  });
  test('override inner chapter canonicalizes, settings exact equality not canonical equality', () {
    final preview = previewFirebaseSchedule(settings(start: 1), plan(start: 53, members: ['a'], weeks: 1));
    expect(preview.assignments.single.unit.key, '51-53'); expect(preview.unfilled.single.unitPosition, 49);
    expect(settings(start: 51) == settings(start: 53), isFalse);
    expect(settings() == settings(), isTrue); expect(settings().hashCode, settings().hashCode);
  });
  test('immutable inputs, rows, unfilled and selected order', () {
    final members = ['z','a']; final p = plan(members: members);
    members[0] = 'changed';
    final preview = previewFirebaseSchedule(settings(start: 53), p);
    expect(p.memberUids, ['z','a']);
    expect(() => p.memberUids.add('x'), throwsUnsupportedError);
    expect(() => preview.assignments.clear(), throwsUnsupportedError);
    expect(() => preview.unfilled.clear(), throwsUnsupportedError);
  });
  test('explicit UTC dates add exactly seven days across DST with JS ms precision', () {
    final date = DateTime.utc(2026, 3, 8, 1, 12, 30, 123, 999);
    final preview = previewFirebaseSchedule(settings(width: 1), plan(members: ['a'], weeks: 3, date: date));
    expect(preview.assignments.map((r) => r.scheduledDate!.toIso8601String()),
      ['2026-03-08T01:12:30.123Z','2026-03-15T01:12:30.123Z','2026-03-22T01:12:30.123Z']);
    expect(() => plan(date: DateTime(2026, 3, 8)), throwsFormatException);
  });
  for (final date in [DateTime.utc(0), DateTime.utc(10000), DateTime.utc(9999,12,31)]) {
    test('Firestore date range including final week $date', () {
      expect(() => previewFirebaseSchedule(settings(), plan(date: date)), throwsFormatException);
    });
  }
  for (final s in [settings(mode: 'other'), settings(mode: ''), settings(width: 0), settings(width: 49),
    settings(start: 0), settings(start: 54), settings(week: 0), settings(week: 10001)]) {
    test('strict settings ${s.mode}/${s.chaptersPerWeek}/${s.startChapter}/${s.currentWeek}', () {
      expect(() => previewFirebaseSchedule(s, plan()), throwsFormatException);
    });
  }
  for (final mode in FirebaseSchedulePlan.modes) {
    test('Saptah label uses the same $mode weekly plan as chapter-wise', () {
      final saptah = previewFirebaseSchedule(settings(mode: 'saptah'), plan(mode: mode));
      final weekly = previewFirebaseSchedule(settings(), plan(mode: mode));
      String row(FirebaseScheduledUnit r) => '${r.userId}/${r.weekNumber}/${r.unit.key}';
      expect(saptah.assignments.map(row), weekly.assignments.map(row));
      expect(saptah.unfilled, weekly.unfilled);
    });
  }
  test('JS golden: extend_last and round_robin finish the book in the last planned week', () {
    final members = ['a', 'b', 'c', 'd'], date = DateTime.utc(2026, 12, 7);
    FirebaseSchedulePreview preview(String remainder, {int start = 4, int width = 2, int weeks = 5}) =>
      previewFirebaseSchedule(settings(width: width, start: start, week: 3),
        plan(members: members, weeks: weeks, remainder: remainder, date: date));
    final truncated = preview('truncate');
    expect(truncated.assignments.length, 40); expect(truncated.extraCount, 0);
    for (final remainder in FirebaseSchedulePlan.finishingRemainders) {
      final result = preview(remainder);
      expect(result.extraCount, 5); expect(result.requestedCount, 40); expect(result.unfilledCount, 0);
      expect(result.assignments.map((r) => r.unit.key), FirebaseChapterUnit.all.skip(3).map((u) => u.key));
      final extras = result.assignments.skip(40).toList();
      expect(extras.every((r) => r.weekNumber == 7 && r.scheduledDate == DateTime.utc(2027, 1, 4)), isTrue);
      expect(extras.map((r) => r.userId), remainder == 'extend_last' ? ['d','d','d','d','d'] : ['a','b','c','d','a']);
      // Exactly one full week (8 units) or more left: nothing is added.
      expect(preview(remainder, start: 1).extraCount, 0);
      expect(preview(remainder, start: 1).assignments.length, 40);
      // Past the book end both behave like truncate.
      final past = preview(remainder, start: 50), reference = preview('truncate', start: 50);
      expect(past.extraCount, 0); expect(past.unfilled, reference.unfilled);
      expect(past.assignments.length, reference.assignments.length);
      expect(past.reviewRequired, isFalse);
    }
  });
  for (final mode in ['', 'unknown']) {
    test('unsupported remainder $mode never substitutes', () {
      expect(() => previewFirebaseSchedule(settings(), plan(remainder: mode)), throwsFormatException);
    });
  }
  for (final mode in ['extend_last', 'round_robin', '', 'unknown']) {
    test('unsupported scheduling $mode never substitutes', () {
      expect(() => previewFirebaseSchedule(settings(), plan(mode: mode)), throwsFormatException);
    });
  }
  for (final members in <List<String>>[[], ['a','a'], [''], ['__reserved__'], ['x/y'], ['é'*751], List.generate(51, (i) => '$i')]) {
    test('member subset strict bounds/segments ${members.length}/${members.isEmpty ? "empty" : members.first.length}', () {
      expect(() => previewFirebaseSchedule(settings(), plan(members: members)), throwsFormatException);
    });
  }
  for (final weeks in [0,13]) {
    test('weeks bound $weeks', () { expect(() => previewFirebaseSchedule(settings(), plan(weeks: weeks)), throwsFormatException); });
  }
  test('week cap inclusive at 10000', () {
    expect(previewFirebaseSchedule(settings(week: 9999), plan()).assignments.last.weekNumber, 10000);
    expect(() => previewFirebaseSchedule(settings(week: 10000), plan()), throwsFormatException);
    expect(previewFirebaseSchedule(settings(week: 10000), plan(weeks: 1)).assignments.last.weekNumber, 10000);
  });
  test('requested slot bound counts omitted slots, max members/weeks accepted', () {
    final members = List.generate(50, (i) => 'u$i');
    final preview = previewFirebaseSchedule(settings(width: 6, start: 53), plan(members: members, weeks: 12));
    expect(preview.requestedCount, 3600);
    expect(preview.assignments.length + preview.unfilledCount, 3600);
    expect(() => previewFirebaseSchedule(settings(width: 7, start: 53), plan(members: members, weeks: 12)), throwsFormatException);
  });
  test('exact4096 requested slots allowed with explicit oversize preview warning', () {
    final preview = previewFirebaseSchedule(settings(width: 32),
      plan(members: List.generate(32, (i) => 'u$i'), weeks: 4, remainder: 'cycle'));
    expect(preview.requestedCount, 4096); expect(preview.assignments.length, 4096);
    expect(preview.commitBlock, isNotNull);
  });
  test('Firestore minimum and maximum valid explicit instants', () {
    for (final date in [DateTime.utc(1), DateTime.utc(9999,12,31,23,59,59,999)]) {
      final preview = previewFirebaseSchedule(settings(width: 1), plan(members: ['a'], weeks: 1, date: date));
      expect(preview.assignments.single.scheduledDate, date);
    }
  });
  test('exact atomic write/member bounds vs larger preview and empty', () {
    final good = previewFirebaseSchedule(settings(width: 4), plan(members: List.generate(12, (i) => '$i'), weeks: 1, mode: 'synchronized'));
    expect(good.assignments.length, 48); expect(good.commitBlock, isNull);
    expect(previewFirebaseSchedule(settings(width: 1), plan(members: List.generate(13, (i) => '$i'), weeks: 1)).commitBlock, isNotNull);
    expect(previewFirebaseSchedule(settings(width: 48), plan(members: ['a'], remainder: 'cycle')).commitBlock, isNotNull);
    expect(previewFirebaseSchedule(settings(start: 53), plan(start: 53, weeks: 2, members: ['a','b'])).commitBlock, isNull);
    // Start at last unit and all later weeks overflow: no invented manual rows.
    expect(previewFirebaseSchedule(settings(width: 1, start: 53), plan(members: ['a'], weeks: 12)).unfilledCount, 11);
  });
  test('UTF8 order at supplementary/BMP boundary', () {
    expect(scheduleUidCompare('\u{10000}', '\uE000'), greaterThan(0));
  });
}