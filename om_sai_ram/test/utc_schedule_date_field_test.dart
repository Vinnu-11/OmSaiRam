import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:om_sai_ram/core/utils/utc_schedule_date.dart';
import 'package:om_sai_ram/shared/widgets/utc_schedule_date_field.dart';

void main() {
  test('UTC timestamp boundary preserves null and JavaScript millisecond precision', () {
    expect(utcScheduleDate(null), isNull);
    expect(utcScheduleDate(DateTime.utc(2026, 3, 8, 18, 30, 1, 123, 456)), DateTime.utc(2026, 3, 8, 18, 30, 1, 123));
    for (final date in [DateTime(2026), DateTime.utc(0), DateTime.utc(10000)]) {
      expect(() => utcScheduleDate(date), throwsFormatException);
    }
    expect(utcScheduleDate(DateTime.utc(9999, 12, 31, 23, 59)), isNotNull);
  });
  Future<void> mount(WidgetTester tester, {DateTime? value, required ValueChanged<DateTime?> changed,
      bool enabled = true, bool Function()? current}) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: UtcScheduleDateField(
      label: 'Scheduled date', value: value, enabled: enabled,
      isCurrent: current ?? () => true, onChanged: changed))));
  }
  testWidgets('null default and cancelled date picker do not invent a date', (tester) async {
    final values = <DateTime?>[]; await mount(tester, changed: values.add);
    expect(find.text('Unscheduled'), findsOneWidget);
    await tester.tap(find.byTooltip('Choose Scheduled date (UTC)')); await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel')); await tester.pumpAndSettle();
    expect(values, isEmpty);
  });
  testWidgets('accepting date then cancelling time makes no change', (tester) async {
    final values = <DateTime?>[];
    await mount(tester, value: DateTime.utc(2026, 10, 15, 18, 30), changed: values.add);
    await tester.tap(find.byTooltip('Choose Scheduled date (UTC)')); await tester.pumpAndSettle();
    await tester.tap(find.text('OK')); await tester.pumpAndSettle();
    expect(find.byType(TimePickerDialog), findsOneWidget);
    await tester.tap(find.text('Cancel')); await tester.pumpAndSettle(); expect(values, isEmpty);
  });
  testWidgets('accepted date and time preserve UTC components, clearing explicitly emits null', (tester) async {
    final values = <DateTime?>[]; final date = DateTime.utc(2026, 10, 15, 18, 30);
    await mount(tester, value: date, changed: values.add);
    await tester.tap(find.byTooltip('Choose Scheduled date (UTC)')); await tester.pumpAndSettle();
    await tester.tap(find.text('OK')); await tester.pumpAndSettle();
    await tester.tap(find.text('OK')); await tester.pumpAndSettle();
    expect(values, [date]); expect(values.single!.isUtc, isTrue);
    await tester.tap(find.byTooltip('Clear Scheduled date')); await tester.pumpAndSettle();
    expect(values, [date, null]);
  });
  testWidgets('changed scope while choosing suppresses callbacks', (tester) async {
    var current = true; final values = <DateTime?>[];
    await mount(tester, value: DateTime.utc(2026, 10, 15), changed: values.add, current: () => current);
    await tester.tap(find.byTooltip('Choose Scheduled date (UTC)')); await tester.pumpAndSettle();
    current = false; await tester.tap(find.text('OK')); await tester.pumpAndSettle();
    expect(find.byType(TimePickerDialog), findsNothing); expect(values, isEmpty);
  });
  testWidgets('disabled picker cannot open or clear', (tester) async {
    await mount(tester, value: DateTime.utc(2026), enabled: false, changed: (_) => fail('disabled change'));
    for (final tooltip in ['Choose Scheduled date (UTC)', 'Clear Scheduled date']) {
      expect(tester.widget<IconButton>(find.widgetWithIcon(IconButton,
        tooltip.startsWith('Choose') ? Icons.calendar_month_outlined : Icons.clear)).onPressed, isNull);
    }
  });
  testWidgets('disposing a bound field dismisses its open native picker without a callback', (tester) async {
    var visible = true; late StateSetter rebuild; final values = <DateTime?>[];
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: StatefulBuilder(builder: (context, setState) {
      rebuild = setState;
      return visible ? UtcScheduleDateField(label: 'Scheduled date', value: null, enabled: true,
        isCurrent: () => visible, onChanged: values.add) : const Text('Changed scope');
    }))));
    await tester.tap(find.byTooltip('Choose Scheduled date (UTC)')); await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);
    rebuild(() => visible = false); await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsNothing); expect(values, isEmpty); expect(tester.takeException(), isNull);
  });
  testWidgets('UTC control wraps at mobile width and large text', (tester) async {
    tester.view.physicalSize = const Size(360, 800); tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: MediaQuery(data: const MediaQueryData(textScaler: TextScaler.linear(2)),
      child: Scaffold(body: Padding(padding: const EdgeInsets.all(24), child: UtcScheduleDateField(
        label: 'First week date', value: DateTime.utc(2026, 10, 15, 18, 30), enabled: true,
        isCurrent: () => true, onChanged: (_) {}))))));
    await tester.pumpAndSettle(); expect(find.text('First week date (UTC)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}