import 'dart:io';
import 'package:scrcpy_mcp/src/agent/clients/llm_client.dart';
import 'package:scrcpy_mcp/src/agent/sop/sop_record.dart';
import 'package:scrcpy_mcp/src/agent/sop/sop_store.dart';
import 'package:scrcpy_mcp/src/agent/sop/sop_writer.dart';
import 'package:test/test.dart';
import '../../utils/fake_model_client.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('sop_w'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('writes a positive SOP from a successful run', () async {
    final store = SopStore(dir.path);
    final writer = SopWriter(
      FakeModelClient(
        ({required messages}) async => const LlmResponse(
          text: '{"intent":"转账","steps":["进聊天","点+"],"pitfall":null}',
        ),
      ),
      store,
    );
    await writer.write(
      package: 'com.app',
      taskText: '给张三转账',
      success: true,
      trajectory: const ['Tap(1,2)', 'Finish("done")'],
    );
    final loaded = await store.load('com.app');
    expect(loaded, hasLength(1));
    expect(loaded.first.polarity, SopPolarity.positive);
    expect(loaded.first.intent, '转账');
    expect(loaded.first.steps, ['进聊天', '点+']);
  });

  test('writes a negative SOP with pitfall from a failed run', () async {
    final store = SopStore(dir.path);
    final writer = SopWriter(
      FakeModelClient(
        ({required messages}) async => const LlmResponse(
          text: '{"intent":"转账","steps":["进聊天"],"pitfall":"被引导蒙层挡住"}',
        ),
      ),
      store,
    );
    await writer.write(
      package: 'com.app',
      taskText: '给张三转账',
      success: false,
      trajectory: const ['Tap(1,2)'],
    );
    final loaded = await store.load('com.app');
    expect(loaded.first.polarity, SopPolarity.negative);
    expect(loaded.first.pitfall, '被引导蒙层挡住');
  });

  test('normalizes literal "null" string to null for positive SOP', () async {
    final store = SopStore(dir.path);
    final writer = SopWriter(
      FakeModelClient(
        ({required messages}) async => const LlmResponse(
          text: '{"intent":"转账","steps":["进聊天","点+"],"pitfall":"null"}',
        ),
      ),
      store,
    );
    await writer.write(
      package: 'com.app',
      taskText: '给张三转账',
      success: true,
      trajectory: const ['Tap(1,2)', 'Finish("done")'],
    );
    final loaded = await store.load('com.app');
    expect(loaded, hasLength(1));
    expect(loaded.first.polarity, SopPolarity.positive);
    expect(loaded.first.pitfall, isNull);
  });
}
