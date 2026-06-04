import 'package:logger_utils/logger_utils.dart';
import 'package:logging/logging.dart' show hierarchicalLoggingEnabled;
import 'package:test/test.dart';

void main() {
  group('dumpValue', () {
    test('quotes strings', () {
      expect(dumpValue('hi'), '"hi"');
    });

    test('renders null, num and bool via toString', () {
      expect(dumpValue(null), 'null');
      expect(dumpValue(42), '42');
      expect(dumpValue(true), 'true');
    });

    test('renders maps inline', () {
      expect(dumpValue({'key': 'value', 'n': 1}), '{ key: "value", n: 1 }');
      expect(dumpValue(<String, Object>{}), '{}');
    });

    test('renders lists multi-line with indent and no indices', () {
      final out = dumpValue([
        {'key': 'a'},
        {'key': 'b'},
      ]);
      expect(out, '[\n   { key: "a" },\n   { key: "b" }\n]');
    });

    test('renders empty list inline', () {
      expect(dumpValue(<Object>[]), '[]');
    });

    test('nests indentation for lists inside lists', () {
      final out = dumpValue([
        ['x'],
      ]);
      expect(out, '[\n   [\n      "x"\n   ]\n]');
    });

    test('guards against cyclic references', () {
      final list = <Object>[];
      list.add(list);
      expect(() => dumpValue(list), returnsNormally);
      expect(dumpValue(list), contains('[...]'));
    });

    test('bounds recursion depth', () {
      Object nested = 'leaf';
      for (var i = 0; i < 10; i++) {
        nested = [nested];
      }
      expect(dumpValue(nested), contains('...'));
    });
  });

  group('Logger.trace', () {
    late Logger log;
    late List<LogRecord> records;
    late void Function() cancel;

    setUp(() {
      hierarchicalLoggingEnabled = true;
      log = Logger('trace.test.${DateTime.now().microsecondsSinceEpoch}');
      records = [];
      final sub = log.onRecord.listen(records.add);
      cancel = sub.cancel;
    });

    tearDown(() => cancel());

    test('logs args and return value at FINE and returns result', () {
      log.level = Level.FINE;
      final result = log.trace('add', [1, 2], () => 1 + 2);

      expect(result, 3);
      expect(records.map((r) => r.message), ['add(1, 2)', 'add => 3']);
      expect(records.every((r) => r.level == Level.FINE), isTrue);
    });

    test(
      'zero overhead when FINE not loggable: no records, call runs once',
      () {
        log.level = Level.INFO;
        var calls = 0;
        final result = log.trace('side', ['x'], () {
          calls++;
          return 'ok';
        });

        expect(result, 'ok');
        expect(calls, 1);
        expect(records, isEmpty);
      },
    );

    test('traceAsync awaits the call and logs the resolved value', () async {
      log.level = Level.FINE;
      final result = await log.traceAsync('fetch', [
        'id',
      ], () async => {'name': 'val'});

      expect(result, {'name': 'val'});
      expect(records.map((r) => r.message), [
        'fetch("id")',
        'fetch => { name: "val" }',
      ]);
    });

    test('traceAsync is zero-overhead when FINE not loggable', () async {
      log.level = Level.INFO;
      var calls = 0;
      final result = await log.traceAsync('a', [], () async {
        calls++;
        return 7;
      });

      expect(result, 7);
      expect(calls, 1);
      expect(records, isEmpty);
    });
  });
}
