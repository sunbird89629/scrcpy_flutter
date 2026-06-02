import 'package:scrcpy_mcp/scrcpy_mcp.dart';
import 'package:test/test.dart';

import 'visual_assertion.dart';

void main() {
  group('parseScreenCheckResponse', () {
    test('leading 是 → matched', () {
      final r = parseScreenCheckResponse('是\n界面上有应用图标');
      expect(r.matched, isTrue);
      expect(r.reason, contains('应用图标'));
    });

    test('bare 是 → matched', () {
      expect(parseScreenCheckResponse('是').matched, isTrue);
    });

    test('leading 否 → not matched, reason preserved', () {
      final r = parseScreenCheckResponse('否\n没有看到');
      expect(r.matched, isFalse);
      expect(r.reason, contains('没有看到'));
    });

    test('不是 → not matched (regression for contains("是") bug)', () {
      expect(parseScreenCheckResponse('不是').matched, isFalse);
    });

    test('leading/trailing whitespace tolerated', () {
      expect(parseScreenCheckResponse('  是  ').matched, isTrue);
    });

    test('only first line decides', () {
      expect(parseScreenCheckResponse('否\n是的部分内容相似').matched, isFalse);
    });

    test('empty → throws LlmException', () {
      expect(() => parseScreenCheckResponse(''), throwsA(isA<LlmException>()));
    });

    test('whitespace-only → throws LlmException', () {
      expect(
        () => parseScreenCheckResponse('   \n  '),
        throwsA(isA<LlmException>()),
      );
    });

    test('unparseable prose → throws LlmException', () {
      expect(
        () => parseScreenCheckResponse('这个界面看起来像桌面'),
        throwsA(isA<LlmException>()),
      );
    });
  });

  group('checkScreenContains', () {
    test('wires messages and parses 是', () async {
      final fake = _FakeLlmClient('是\n有图标');
      final r = await checkScreenContains(
        client: fake,
        base64Screenshot: 'AAAA',
        expectation: '应用图标',
      );
      expect(r.matched, isTrue);

      final msgs = fake.captured!;
      expect(msgs.first.role, 'system');
      expect(msgs.first.textContent, contains('手机界面分析助手'));
      final user = msgs.last;
      expect(user.role, 'user');
      expect(user.textContent, contains('应用图标'));
      expect(user.imageBase64, 'AAAA');
      expect(user.imageMimeType, 'image/png');
    });

    test('parses 否 as not matched', () async {
      final r = await checkScreenContains(
        client: _FakeLlmClient('否'),
        base64Screenshot: 'AAAA',
        expectation: '计算器',
      );
      expect(r.matched, isFalse);
    });

    test('empty model reply throws LlmException', () async {
      await expectLater(
        () => checkScreenContains(
          client: _FakeLlmClient(''),
          base64Screenshot: 'AAAA',
          expectation: 'x',
        ),
        throwsA(isA<LlmException>()),
      );
    });
  });
}

class _FakeLlmClient implements LlmClient {
  _FakeLlmClient(this.reply);

  final String reply;
  List<LlmMessage>? captured;

  @override
  Future<LlmResponse> chat({required List<LlmMessage> messages}) async {
    captured = messages;
    return LlmResponse(text: reply);
  }
}
