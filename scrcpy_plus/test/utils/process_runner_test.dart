import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_plus/utils/process_runner.dart';

void main() {
  group('ProcessRunner', () {
    test('run returns stdout on success', () async {
      final runner = ProcessRunner();
      final result = await runner.run('echo', ['hello']);
      expect(result.exitCode, 0);
      expect(result.stdout.toString().trim(), 'hello');
    });

    test('run returns non-zero exit on failure', () async {
      final runner = ProcessRunner();
      final result = await runner.run('false', []);
      expect(result.exitCode, isNot(0));
    });
  });
}
