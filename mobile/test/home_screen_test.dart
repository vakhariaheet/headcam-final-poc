import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/screens/home_screen.dart';
import 'package:mobile/state/shell_navigation_provider.dart';

void main() {
  Widget wrap(Widget child, {ProviderContainer? container}) {
    final content = MaterialApp(
      home: child,
      routes: {
        '/discovery': (_) => const Scaffold(body: Text('Discovery Screen')),
        '/select-hat': (_) => const Scaffold(body: Text('Select Hat Screen')),
        '/match-setup': (_) => const Scaffold(body: Text('Match Setup Screen')),
      },
    );
    return container == null
        ? ProviderScope(child: content)
        : UncontrolledProviderScope(container: container, child: content);
  }

  testWidgets(
    'shows a greeting, an unpaired device card, and a channel banner',
    (tester) async {
      await tester.pumpWidget(wrap(const HomeScreen()));
      await tester.pump();

      expect(find.text('Not connected'), findsOneWidget);
      expect(find.text('Pair New Hat'), findsOneWidget);
      expect(find.text('Connect a broadcast channel'), findsOneWidget);
      expect(find.text('Recent Recordings'), findsOneWidget);
      expect(find.text('No recordings yet.'), findsOneWidget);
    },
  );

  testWidgets('Pair New Hat navigates to /discovery', (tester) async {
    await tester.pumpWidget(wrap(const HomeScreen()));
    await tester.pump();

    await tester.tap(find.text('Pair New Hat'));
    await tester.pumpAndSettle();

    expect(find.text('Discovery Screen'), findsOneWidget);
  });

  testWidgets('the channel banner switches the shell to the Settings tab', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(wrap(const HomeScreen(), container: container));
    await tester.pump();

    await tester.tap(find.text('Connect a broadcast channel'));
    await tester.pump();

    expect(container.read(selectedShellTabProvider), ShellTab.settings);
  });
}
