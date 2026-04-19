import 'package:autoglm_core/autoglm_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('autoglm_core library imports without throwing', () {
    // Verify the barrel re-exports are reachable.
    const s = Settings();
    expect(s, isNotNull);
  });
}
