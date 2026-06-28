// test/agent_prompts_test.dart
import 'package:scrcpy_mcp/src/agent/agent_prompts.dart';
import 'package:test/test.dart';

void main() {
  group('kOfficialPrompt', () {
    test('contains no think/answer/memory tags', () {
      for (final token in ['<think>', '<answer>', '<memory>']) {
        expect(kOfficialPrompt.contains(token), isFalse, reason: token);
      }
    });
    test('keeps the do() action vocabulary and coordinate space', () {
      for (final a in [
        'do(action="Launch"',
        'do(action="Tap"',
        'do(action="Swipe"',
        'finish(message=',
        '(999,999)',
      ]) {
        expect(kOfficialPrompt.contains(a), isTrue, reason: a);
      }
    });
    test('retains the numbered rules and runtime placeholders', () {
      expect(kOfficialPrompt.contains('{DATE}'), isTrue);
      expect(kOfficialPrompt.contains('{SCREEN_SIZE}'), isTrue);
      expect(kOfficialPrompt.contains('17.'), isTrue);
    });
  });

  group('kOpenSourcePrompt', () {
    test('keeps the think/answer/memory format', () {
      for (final token in ['<think>', '<answer>', '<memory>']) {
        expect(kOpenSourcePrompt.contains(token), isTrue, reason: token);
      }
    });
  });
}
