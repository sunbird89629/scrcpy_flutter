import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_view_example/main.dart';

void main() {
  testWidgets('App renders', (WidgetTester tester) async {
    await tester.pumpWidget(const ExampleApp());
    expect(find.text('ScrcpyView Example'), findsOneWidget);
  });
}
