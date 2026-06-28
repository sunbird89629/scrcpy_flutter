import 'package:scrcpy_mcp/src/agent/sop/foreground_package.dart';
import 'package:test/test.dart';

void main() {
  test('parses package from mResumedActivity line', () {
    const out = '''
  ResumedActivity: ActivityRecord{a1b2 u0 com.tencent.mm/.ui.LauncherUI t42}
  mResumedActivity: ActivityRecord{a1b2 u0 com.tencent.mm/.ui.LauncherUI t42}
''';
    expect(parseForegroundPackage(out), 'com.tencent.mm');
  });

  test('returns null when no resumed activity present', () {
    expect(parseForegroundPackage('nothing here'), isNull);
  });
}
