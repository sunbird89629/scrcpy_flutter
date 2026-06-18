import 'package:scrcpy_mcp/src/agent/sop/sop_record.dart';
import 'package:test/test.dart';

void main() {
  test('toJson/fromJson round-trips', () {
    final r = SopRecord(
      id: 'abc',
      package: 'com.tencent.mm',
      intent: '给联系人转账',
      polarity: SopPolarity.negative,
      steps: const ['进入聊天', '点右下 +'],
      pitfall: '先关引导蒙层',
      sourceTask: '给张三转 100',
      createdAt: DateTime.utc(2026, 6, 18, 10),
      deviceHint: '1080x2340 zh-CN',
    );
    final back = SopRecord.fromJson(r.toJson());
    expect(back.id, 'abc');
    expect(back.polarity, SopPolarity.negative);
    expect(back.steps, ['进入聊天', '点右下 +']);
    expect(back.pitfall, '先关引导蒙层');
    expect(back.createdAt, DateTime.utc(2026, 6, 18, 10));
  });

  test('fromJson defaults missing optional fields', () {
    final back = SopRecord.fromJson({
      'id': 'x',
      'package': 'p',
      'intent': 'i',
      'polarity': 'positive',
      'steps': ['a'],
      'source_task': 't',
      'created_at': '2026-06-18T10:00:00.000Z',
    });
    expect(back.polarity, SopPolarity.positive);
    expect(back.pitfall, isNull);
    expect(back.deviceHint, isNull);
  });
}
