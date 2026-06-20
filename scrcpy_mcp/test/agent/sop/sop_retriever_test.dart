import 'package:scrcpy_mcp/src/agent/clients/llm_client.dart';
import 'package:scrcpy_mcp/src/agent/sop/sop_record.dart';
import 'package:scrcpy_mcp/src/agent/sop/sop_retriever.dart';
import 'package:test/test.dart';
import '../../utils/fake_model_client.dart';

SopRecord rec(String id, String intent) => SopRecord(
  id: id,
  package: 'com.app',
  intent: intent,
  polarity: SopPolarity.positive,
  steps: const ['a'],
  sourceTask: 't',
  createdAt: DateTime.utc(2026, 6, 18),
);

void main() {
  test('returns [] without calling LLM when no candidates', () async {
    var called = false;
    final r = SopRetriever(
      FakeModelClient(({required messages}) async {
        called = true;
        return const LlmResponse(text: '0');
      }),
    );
    expect(await r.select(taskText: 'x', candidates: const []), isEmpty);
    expect(called, isFalse);
  });

  test('selects records by LLM-returned indices, capped at limit', () async {
    final r = SopRetriever(
      FakeModelClient(
        ({required messages}) async => const LlmResponse(text: '相关：2, 0'),
      ),
    );
    final picked = await r.select(
      taskText: '转账',
      candidates: [rec('a', '充值'), rec('b', '设置'), rec('c', '转账')],
    );
    expect(picked.map((p) => p.id), ['c', 'a']);
  });
}
