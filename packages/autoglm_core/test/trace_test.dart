import 'dart:convert';
import 'dart:io';
import 'package:autoglm_core/src/trace/trace_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('TraceManager', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('trace_test');
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test('records spans to daily file', () async {
      final manager = TraceManager(logsDir: tempDir.path)
        ..startTrace('test-trace');

      final spanId = manager.startSpan('test.span');
      final start = DateTime.now();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await manager.endSpan(
        spanId,
        name: 'test.span',
        startTime: start,
        endTime: DateTime.now(),
      );

      final date = DateTime.now().toIso8601String().split('T').first;
      final file = File(p.join(tempDir.path, 'trace_$date.jsonl'));
      expect(file.existsSync(), isTrue);

      final line = file.readAsLinesSync().first;
      final json = jsonDecode(line) as Map<String, dynamic>;
      expect(json['trace_id'], 'test-trace');
      expect(json['name'], 'test.span');
      expect(json['duration_ms'], greaterThanOrEqualTo(10));
    });
  });
}
