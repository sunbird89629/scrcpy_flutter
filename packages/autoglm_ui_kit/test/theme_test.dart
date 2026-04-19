import 'package:autoglm_ui_kit/autoglm_ui_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('themes', () {
    test('lightTheme is Material 3 with light brightness', () {
      expect(lightTheme.useMaterial3, isTrue);
      expect(lightTheme.brightness, Brightness.light);
    });

    test('darkTheme is Material 3 with dark brightness', () {
      expect(darkTheme.useMaterial3, isTrue);
      expect(darkTheme.brightness, Brightness.dark);
    });

    testWidgets('lightTheme can be applied to MaterialApp', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: lightTheme,
          home: const Scaffold(body: Text('hi')),
        ),
      );
      expect(find.text('hi'), findsOneWidget);
    });
  });
}
