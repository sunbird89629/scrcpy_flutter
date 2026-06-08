import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:scrcpy_mcp/scrcpy_mcp.dart';
import 'package:test/test.dart';

import 'agent_eval_case.dart';
import 'agent_eval_failure.dart';
import 'agent_eval_result.dart';
import 'agent_eval_runner.dart';

class _FakeEvalActionRunner {
  final actions = <DoAction>[];

  Future<String> call(PhoneAction action) async {
    if (action is DoAction) {
      actions.add(action);
      return 'ran ${action.action}';
    }
    return '(finish)';
  }
}

void _expectFileExists(String path) {
  expect(File(path).existsSync(), isTrue, reason: '$path should exist');
}

class _ArtifactAdb implements ScrcpyMcpAdb {
  @override
  Future<List<String>> getDevices() async => ['device1'];

  @override
  Future<ProcessResult> shell(
    List<String> arguments, {
    String? deviceId,
    Duration timeout = const Duration(seconds: 30),
  }) async => ProcessResult(0, 0, '', '');

  @override
  Future<void> forward(
    String local,
    String remote, {
    String? deviceId,
    bool noRebind = false,
  }) async {}

  @override
  Future<void> forwardRemove(String local, {String? deviceId}) async {}

  @override
  Future<void> push(
    String localPath,
    String remotePath, {
    String? deviceId,
  }) async {}

  @override
  Future<Process> startProcess(List<String> arguments) {
    throw UnimplementedError();
  }

  @override
  Future<Uint8List> takeScreenshot(String deviceId) async =>
      Uint8List.fromList([1]);

  @override
  Future<RecordingProcess> startScreenrecord(
    String deviceId,
    String remotePath, {
    int bitrate = 4000000,
    int maxTime = 180,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> pullFile(
    String deviceId,
    String remotePath,
    String localPath,
  ) async {}

  @override
  Future<void> removeFile(String deviceId, String remotePath) async {}
}

void main() {
  group('AgentEvalFailureKind', () {
    test('classifies known agent failure text', () {
      expect(
        classifyAgentFailure('Could not parse an action (bad): text'),
        AgentEvalFailureKind.parseFailure,
      );
      expect(
        classifyAgentFailure(
          'Max steps (30) reached without completing the task.',
        ),
        AgentEvalFailureKind.maxSteps,
      );
      expect(
        classifyAgentFailure(
          'Aborted: screen unchanged for 4 consecutive steps',
        ),
        AgentEvalFailureKind.stalled,
      );
      expect(
        classifyAgentFailure('Aborted: repeated the same action 10 times'),
        AgentEvalFailureKind.repeatedAction,
      );
      expect(
        classifyAgentFailure('Task requires human: login needed'),
        AgentEvalFailureKind.humanRequired,
      );
    });

    test('unknown text maps to unknown', () {
      expect(
        classifyAgentFailure('some unexpected result'),
        AgentEvalFailureKind.unknown,
      );
    });
  });

  group('AgentEvalResult', () {
    test('serializes to JSON', () {
      final result = AgentEvalResult(
        caseId: 'case1',
        success: false,
        failureKind: AgentEvalFailureKind.maxSteps,
        finalResult: 'Max steps (3) reached',
        steps: 3,
        duration: const Duration(milliseconds: 42),
        assertions: const [
          AgentEvalAssertionResult(
            kind: 'text_contains',
            passed: false,
            reason: 'Expected final result to contain "done".',
          ),
        ],
      );

      expect(result.toJson(), {
        'caseId': 'case1',
        'success': false,
        'failureKind': 'maxSteps',
        'finalResult': 'Max steps (3) reached',
        'steps': 3,
        'durationMs': 42,
        'assertions': [
          {
            'kind': 'text_contains',
            'passed': false,
            'reason': 'Expected final result to contain "done".',
          },
        ],
      });
    });
  });

  group('TextContainsAssertion', () {
    test('passes when final text contains expected substring', () {
      const assertion = TextContainsAssertion('done');
      final result = assertion.evaluateText('task done');

      expect(result.kind, 'text_contains');
      expect(result.passed, isTrue);
      expect(result.reason, contains('done'));
    });

    test('fails when final text misses expected substring', () {
      const assertion = TextContainsAssertion('done');
      final result = assertion.evaluateText('still running');

      expect(result.kind, 'text_contains');
      expect(result.passed, isFalse);
      expect(result.reason, contains('done'));
    });
  });

  group('AgentEvalRunner', () {
    test('writes result and step artifacts for a successful case', () async {
      final temp = await Directory.systemTemp.createTemp('agent_eval_test_');
      addTearDown(() => temp.delete(recursive: true));

      var screenshotCount = 0;
      final actionRunner = _FakeEvalActionRunner();
      final runner = AgentEvalRunner(
        outputRoot: temp,
        deviceId: 'device1',
        adb: _ArtifactAdb(),
        chat: ({required messages}) async {
          if (messages.length == 2) {
            return const LlmResponse(
              text: 'do(action="Tap", element=[500,300])',
            );
          }
          return const LlmResponse(text: 'finish(message="done")');
        },
        screenshotProvider: () async {
          screenshotCount++;
          return Uint8List.fromList([screenshotCount]);
        },
        actionRunner: actionRunner.call,
      );

      final result = await runner.runCase(
        const AgentEvalCase(
          id: 'fake_case',
          description: 'fake',
          task: 'tap then finish',
          config: AgentConfig(maxSteps: 3),
          assertions: [TextContainsAssertion('done')],
        ),
      );

      expect(result.success, isTrue);
      expect(result.failureKind, isNull);
      expect(actionRunner.actions, hasLength(1));

      final caseDir = Directory('${temp.path}/fake_case');
      _expectFileExists('${caseDir.path}/result.json');
      _expectFileExists('${caseDir.path}/steps.jsonl');
      _expectFileExists('${caseDir.path}/final.txt');

      final resultJson =
          jsonDecode(File('${caseDir.path}/result.json').readAsStringSync())
              as Map<String, dynamic>;
      expect(resultJson['success'], isTrue);
      expect(resultJson['caseId'], 'fake_case');

      final stepLines = File('${caseDir.path}/steps.jsonl')
          .readAsLinesSync()
          .where((line) => line.isNotEmpty)
          .map((line) => jsonDecode(line) as Map<String, dynamic>)
          .toList();
      expect(stepLines.map((e) => e['type']), contains('screenshot'));
      expect(stepLines.map((e) => e['type']), contains('action'));
      expect(stepLines.map((e) => e['type']), contains('assertion'));
      expect(stepLines.map((e) => e['type']), contains('final'));
    });
  });
}
