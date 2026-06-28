import 'dart:io';
import 'package:scrcpy_mcp/src/agent/sop/sop_record.dart';
import 'package:scrcpy_mcp/src/agent/sop/sop_store.dart';
import 'package:test/test.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('sop_test'));
  tearDown(() => dir.deleteSync(recursive: true));

  SopRecord rec(String id) => SopRecord(
    id: id,
    package: 'com.app',
    intent: 'i$id',
    polarity: SopPolarity.positive,
    steps: const ['a'],
    sourceTask: 't',
    createdAt: DateTime.utc(2026, 6, 18),
  );

  test('append then load returns records in order', () async {
    final store = SopStore(dir.path);
    await store.append(rec('1'));
    await store.append(rec('2'));
    final loaded = await store.load('com.app');
    expect(loaded.map((r) => r.id), ['1', '2']);
  });

  test('load returns empty for unknown package', () async {
    expect(await SopStore(dir.path).load('nope'), isEmpty);
  });

  test('load skips a corrupt line', () async {
    final store = SopStore(dir.path);
    await store.append(rec('1'));
    final f = File('${dir.path}/sop/com.app.jsonl');
    f.writeAsStringSync('{not json\n', mode: FileMode.append);
    await store.append(rec('2'));
    final loaded = await store.load('com.app');
    expect(loaded.map((r) => r.id), ['1', '2']);
  });
}
