import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sabibom/core/widgets/app_scroll_padding.dart';

void main() {
  testWidgets('safe scroll padding includes the device bottom inset', (
    tester,
  ) async {
    late EdgeInsets padding;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(viewPadding: EdgeInsets.only(bottom: 24)),
          child: Builder(
            builder: (context) {
              padding = appSafeScrollPadding(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    expect(padding.left, 16);
    expect(padding.top, 16);
    expect(padding.right, 16);
    expect(padding.bottom, 56);
  });
}
