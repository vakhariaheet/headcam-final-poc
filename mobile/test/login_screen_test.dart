import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/screens/login_screen.dart';

void main() {
  Widget wrap(Widget child) => ProviderScope(child: MaterialApp(home: child));

  testWidgets('shows validation errors for empty fields', (tester) async {
    await tester.pumpWidget(wrap(const LoginScreen()));

    await tester.tap(find.text('Sign In'));
    await tester.pump();

    expect(find.text('Enter a valid email'), findsOneWidget);
    expect(find.text('Enter your password'), findsOneWidget);
  });

  testWidgets('shows an error for a malformed email without calling the API', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(const LoginScreen()));

    await tester.enterText(
      find.byKey(const Key('loginEmailField')),
      'not-an-email',
    );
    await tester.enterText(
      find.byKey(const Key('loginPasswordField')),
      'password123',
    );
    await tester.tap(find.text('Sign In'));
    await tester.pump();

    expect(find.text('Enter a valid email'), findsOneWidget);
    // Validation fails client-side, so no loading spinner from a real
    // network call should ever appear.
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
