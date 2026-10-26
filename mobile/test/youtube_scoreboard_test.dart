import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/models/cloud_status.dart';
import 'package:mobile/widgets/scoreboard_editor.dart';

void main() {
  test('initializing and reconnecting preserve the active broadcast', () {
    for (final state in ['INITIALIZING', 'LIVE', 'RECONNECTING']) {
      expect(CloudStatus(status: state).isActive, isTrue);
    }
    expect(const CloudStatus(status: 'FAILED').isActive, isFalse);
    expect(const CloudStatus(status: 'TERMINATED').isActive, isFalse);
  });

  testWidgets('invalid overs cannot be sent; valid score is saved', (
    tester,
  ) async {
    Map<String, dynamic>? saved;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ScoreboardEditor(
                onSave: (score) async {
                  saved = score;
                },
              ),
            ),
          ),
        ),
      ),
    );
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(2), '123');
    await tester.enterText(fields.at(4), '12.6');
    final save = find.text('Save scoreboard');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pump();
    expect(saved, isNull);
    expect(find.text('Use completed overs and balls 0–5'), findsOneWidget);
    await tester.enterText(fields.at(4), '12.3');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(saved?['runs'], 123);
    expect(saved?['overs'], '12.3');
  });
}
