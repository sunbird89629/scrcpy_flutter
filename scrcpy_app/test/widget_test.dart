import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_app/main.dart';

void main() {
  testWidgets('App renders', (WidgetTester tester) async {
    await tester.pumpWidget(const ScrcpyApp());
    expect(find.text('Scrcpy'), findsOneWidget);
  });
}
