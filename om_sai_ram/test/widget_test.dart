// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:om_sai_ram/app.dart';
import 'package:om_sai_ram/core/config/backend_config.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    // Legacy shell: Firebase is the default and needs a bootstrapped SDK.
    await tester.pumpWidget(ProviderScope(overrides: [
      backendConfigProvider.overrideWithValue(BackendConfig.parse(
          mode: 'fastapi', debug: true, web: false, platform: TargetPlatform.android)),
    ], child: const OmSaiRamApp()));
    await tester.pump();
    expect(find.text('Om Sai Ram'), findsAny);
  });
}
