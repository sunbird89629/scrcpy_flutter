import 'package:scrcpy_mcp/src/agent/response_parser.dart';
import 'package:test/test.dart';

void main() {
  group('ResponseParser', () {
    DoAction expectDo(String text) {
      final parsed = ResponseParser.parse(text);
      expect(parsed, isA<ParsedAction>());
      final action = (parsed as ParsedAction).action;
      expect(action, isA<DoAction>());
      return action as DoAction;
    }

    FinishAction expectFinish(String text) {
      final parsed = ResponseParser.parse(text);
      expect(parsed, isA<ParsedAction>());
      final action = (parsed as ParsedAction).action;
      expect(action, isA<FinishAction>());
      return action as FinishAction;
    }

    test('parses do() with keyword args', () {
      final a = expectDo('do(action="Tap", element=[500, 300])');
      expect(a.action, 'Tap');
      expect(a.element, [500, 300]);
    });

    test('parses finish()', () {
      final f = expectFinish('finish(message="All done")');
      expect(f.message, 'All done');
    });

    test('finish() tolerates unescaped inner quotes', () {
      const content =
          '否，界面上没有出现"Twitter（X）的主页"。\n'
          'finish(message="否，界面上没有出现"Twitter（X）的主页"。")';
      final f = expectFinish(content);
      expect(f.message, startsWith('否，界面上没有出现'));
      expect(f.message, isNot(contains('message=')));
      expect(f.message, contains('"Twitter（X）的主页"'));
    });

    test('do() free-text field tolerates unescaped inner quotes', () {
      final a = expectDo('do(action="Type", text="他说"你好"")');
      expect(a.action, 'Type');
      expect(a.text, '他说"你好"');
    });

    test('parses inside <answer> tags', () {
      final a = expectDo('<answer>do(action="Tap", element=[100, 200])</answer>');
      expect(a.action, 'Tap');
      expect(a.element, [100, 200]);
    });

    test('tolerates natural-language prefix before the action', () {
      final a = expectDo('Let me tap it.\ndo(action="Back")');
      expect(a.action, 'Back');
    });

    test('splits <think> into think, keeps the rest as content', () {
      final parsed = ResponseParser.parse(
        '<think>冗长推理</think>do(action="Tap", element=[1, 2])',
      );
      expect(parsed, isA<ParsedAction>());
      expect(parsed.think, '冗长推理');
      expect(parsed.content, isNot(contains('<think>')));
      expect(parsed.content, isNot(contains('冗长推理')));
      expect(parsed.content, contains('do(action'));
    });

    test('parses Call_API instruction into message', () {
      final a = expectDo('do(action="Call_API", instruction="总结当前页面")');
      expect(a.action, 'Call_API');
      expect(a.message, '总结当前页面');
    });

    test('parses sensitive Tap with message', () {
      final a = expectDo('do(action="Tap", element=[10, 20], message="重要操作")');
      expect(a.action, 'Tap');
      expect(a.element, [10, 20]);
      expect(a.message, '重要操作');
    });

    test('ParseFailure on empty response', () {
      final parsed = ResponseParser.parse('');
      expect(parsed, isA<ParseFailure>());
      expect((parsed as ParseFailure).reason, contains('empty'));
    });

    test('ParseFailure on think-only response', () {
      final parsed = ResponseParser.parse('<think>只有推理没有动作</think>');
      expect(parsed, isA<ParseFailure>());
      expect((parsed as ParseFailure).reason, contains('empty'));
    });

    test('ParseFailure on prose with no action token', () {
      final parsed = ResponseParser.parse('这是一段没有任何动作的普通文本');
      expect(parsed, isA<ParseFailure>());
      expect((parsed as ParseFailure).reason, contains('no action token'));
    });

    test('ParseFailure on malformed do() missing action', () {
      final parsed = ResponseParser.parse('do(element=[1,2])');
      expect(parsed, isA<ParseFailure>());
      expect((parsed as ParseFailure).reason, contains('malformed do()'));
    });

    test('no think/answer tags: think is empty, content is the action', () {
      final parsed = ResponseParser.parse('do(action="Back")');
      expect(parsed, isA<ParsedAction>());
      expect(parsed.think, '');
      expect(parsed.content, 'do(action="Back")');
    });

    test('extracts <memory> when present', () {
      final parsed = ResponseParser.parse(
        '<think>推理</think>'
        '<memory>视频1: "赛博参观极客湾" - 19:27</memory>\n'
        'do(action="Tap", element=[1, 2])',
      );
      expect(parsed.memory, '视频1: "赛博参观极客湾" - 19:27');
      expect(parsed, isA<ParsedAction>());
      final a = (parsed as ParsedAction).action as DoAction;
      expect(a.action, 'Tap');
      expect(a.element, [1, 2]);
    });

    test('<memory> is optional / absent → memory is empty', () {
      final parsed = ResponseParser.parse('do(action="Back")');
      expect(parsed.memory, '');
      expect(parsed, isA<ParsedAction>());
    });

    test('<memory> multiline content preserved verbatim', () {
      final parsed = ResponseParser.parse(
        '<think>t</think>\n'
        '<memory>视频1: "A" - 1万\n视频2: "B" - 2万</memory>\n'
        'do(action="Tap", element=[1, 2])',
      );
      expect(parsed.memory, '视频1: "A" - 1万\n视频2: "B" - 2万');
    });

    test('<think> + <memory> + <answer> together', () {
      final parsed = ResponseParser.parse(
        '<think>推理</think>\n'
        '<memory>记东西</memory>\n'
        '<answer>do(action="Back")</answer>',
      );
      expect(parsed.think, '推理');
      expect(parsed.memory, '记东西');
      expect(parsed, isA<ParsedAction>());
    });

    test('handles <think> and <answer> together', () {
      final parsed = ResponseParser.parse(
        '<think>推理</think>\n<answer>do(action="Tap", element=[5, 6])</answer>',
      );
      expect(parsed, isA<ParsedAction>());
      expect(parsed.think, '推理');
      final a = (parsed as ParsedAction).action as DoAction;
      expect(a.element, [5, 6]);
    });
  });
}
