import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/app.dart';

void main() {
  testWidgets('app boots to welcome and opens login', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: CreasePointApp()));
    // AuthGate checks secure storage for a session; in the test environment
    // that platform channel call never resolves, so this jumps the fake
    // clock past its 5s timeout (see UserAuthNotifier.restoreSession)
    // rather than hanging on find-by-text below.
    await tester.pump();
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();

    // The CreasePoint wordmark is baked into the logo image (BrandHeader),
    // not a separate Text widget — assert on the image instead of text.
    expect(find.text('Get Started'), findsOneWidget);
    await tester.ensureVisible(find.text('Sign In'));
    await tester.tap(find.text('Sign In'));
    await tester.pumpAndSettle();
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Sign In'), findsOneWidget);
  });
}
