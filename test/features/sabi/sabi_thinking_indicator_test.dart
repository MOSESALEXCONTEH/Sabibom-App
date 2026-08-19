import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sabibom/features/sabi/presentation/widgets/sabi_thinking_indicator.dart';

void main() {
  testWidgets('thinking indicator scales down without horizontal overflow', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(width: 105, child: SabiThinkingIndicator()),
          ),
        ),
      ),
    );

    expect(find.text('Sabi is thinking…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
