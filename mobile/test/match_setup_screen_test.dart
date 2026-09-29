import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/screens/match_setup_screen.dart';

void main() {
  Widget wrap(Widget child) => ProviderScope(child: MaterialApp(home: child));

  testWidgets('shows an error for an invalid URL', (tester) async {
    await tester.pumpWidget(wrap(const MatchSetupScreen()));

    await tester.enterText(find.byKey(const Key('matchUrlField')), 'not a url');
    await tester.pump();

    expect(
      find.text("That doesn't look like a CricHeroes match URL."),
      findsOneWidget,
    );
    expect(find.byKey(const Key('matchBadge')), findsNothing);
  });

  testWidgets('shows the parsed match badge for a valid URL', (tester) async {
    await tester.pumpWidget(wrap(const MatchSetupScreen()));

    await tester.enterText(
      find.byKey(const Key('matchUrlField')),
      'https://cricheroes.com/match/scorecard/9482014/final-super-strikers-vs-royal-lions',
    );
    await tester.pump();

    expect(find.byKey(const Key('matchBadge')), findsOneWidget);
    expect(find.text('Match ID: 9482014'), findsOneWidget);
  });

  testWidgets('does not overflow with a shrunk viewport (simulated keyboard)', (
    tester,
  ) async {
    // Regression test: the body used to rely on Spacer() inside a
    // non-scrolling Column, which overflowed once the on-screen keyboard
    // reduced the available height. Body is now a SingleChildScrollView.
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.physicalSize = const Size(390, 400);
    tester.view.devicePixelRatio = 1.0;

    await tester.pumpWidget(wrap(const MatchSetupScreen()));
    await tester.enterText(
      find.byKey(const Key('matchUrlField')),
      'https://cricheroes.com/match/scorecard/9482014/final',
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
