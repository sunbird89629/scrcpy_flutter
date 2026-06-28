# Agent Eval Harness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a local true-device evaluation harness for `PhoneAgent` that runs fixed cases, records artifacts, and classifies failures.

**Architecture:** Keep the harness entirely under `test/phone_agent_eval/` so it does not affect the shipped MCP API. Cases are Dart objects, the runner wraps existing `PhoneAgent` inputs to record screenshots/actions/results, and tests use fakes for deterministic unit coverage while real-device cases are gated by `SCRCPY_RUN_AGENT_EVAL=1`.

**Tech Stack:** Dart 3.10, `package:test`, existing `PhoneAgent`, `AgentConfig`, `ChatFn`, `ScrcpyMcpAdb`, `AdbActionRunner`, and `test/phone_agent_test/utils/visual_assertion.dart`.

---

## File Structure

- Create `test/phone_agent_eval/agent_eval_failure.dart`
  - Defines `AgentEvalFailureKind` and `classifyAgentFailure(String)`.
- Create `test/phone_agent_eval/agent_eval_result.dart`
  - Defines assertion result and eval result models with JSON serialization.
- Create `test/phone_agent_eval/agent_eval_case.dart`
  - Defines `AgentEvalCase`, `AgentEvalDevice`, and assertion classes.
- Create `test/phone_agent_eval/agent_eval_runner.dart`
  - Implements artifact writing, wrapped screenshot/action/chat recording, assertion evaluation, and `runCase`.
- Create `test/phone_agent_eval/agent_eval_test.dart`
  - Unit tests for classification, result JSON, text assertions, and artifact writing.
- Create `test/phone_agent_eval/cases/settings_navigation.dart`
  - Lightweight settings navigation case.
- Create `test/phone_agent_eval/cases/twitter_home.dart`
  - Twitter/X homepage case.
- Create `test/phone_agent_eval/cases/youtube_history_recent.dart`
  - YouTube history case.
- Create `test/phone_agent_eval/agent_eval_real_device_test.dart`
  - Environment-gated real-device suite.

## Task 1: Failure Classification

**Files:**
- Create: `test/phone_agent_eval/agent_eval_failure.dart`
- Test: `test/phone_agent_eval/agent_eval_test.dart`

- [ ] **Step 1: Write failing tests for failure classification**

Create `test/phone_agent_eval/agent_eval_test.dart` with:

```dart
import 'package:test/test.dart';

import 'agent_eval_failure.dart';

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
        classifyAgentFailure('Aborted: screen unchanged for 4 consecutive steps'),
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
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
dart test test/phone_agent_eval/agent_eval_test.dart
```

Expected: FAIL because `agent_eval_failure.dart` does not exist.

- [ ] **Step 3: Implement failure classification**

Create `test/phone_agent_eval/agent_eval_failure.dart`:

```dart
enum AgentEvalFailureKind {
  parseFailure,
  maxSteps,
  stalled,
  repeatedAction,
  humanRequired,
  toolError,
  textAssertionFailed,
  visualAssertionFailed,
  unknown,
}

AgentEvalFailureKind classifyAgentFailure(String result) {
  if (result.contains('Could not parse an action')) {
    return AgentEvalFailureKind.parseFailure;
  }
  if (result.contains('Max steps')) {
    return AgentEvalFailureKind.maxSteps;
  }
  if (result.contains('screen unchanged') || result.contains('unchanged')) {
    return AgentEvalFailureKind.stalled;
  }
  if (result.contains('repeated the same action')) {
    return AgentEvalFailureKind.repeatedAction;
  }
  if (result.contains('requires human')) {
    return AgentEvalFailureKind.humanRequired;
  }
  return AgentEvalFailureKind.unknown;
}
```

- [ ] **Step 4: Run classification tests**

Run:

```bash
dart test test/phone_agent_eval/agent_eval_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add test/phone_agent_eval/agent_eval_failure.dart test/phone_agent_eval/agent_eval_test.dart
git commit -m "test(agent-eval): classify agent failures"
```

## Task 2: Result Models and Text Assertions

**Files:**
- Create: `test/phone_agent_eval/agent_eval_result.dart`
- Create: `test/phone_agent_eval/agent_eval_case.dart`
- Modify: `test/phone_agent_eval/agent_eval_test.dart`

- [ ] **Step 1: Add failing tests for JSON and text assertions**

Append these imports to `test/phone_agent_eval/agent_eval_test.dart`:

```dart
import 'agent_eval_case.dart';
import 'agent_eval_result.dart';
```

Append these groups inside `main()`:

```dart
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
      final assertion = const TextContainsAssertion('done');
      final result = assertion.evaluateText('task done');

      expect(result.kind, 'text_contains');
      expect(result.passed, isTrue);
      expect(result.reason, contains('done'));
    });

    test('fails when final text misses expected substring', () {
      final assertion = const TextContainsAssertion('done');
      final result = assertion.evaluateText('still running');

      expect(result.kind, 'text_contains');
      expect(result.passed, isFalse);
      expect(result.reason, contains('done'));
    });
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
dart test test/phone_agent_eval/agent_eval_test.dart
```

Expected: FAIL because model and assertion types are missing.

- [ ] **Step 3: Implement result model**

Create `test/phone_agent_eval/agent_eval_result.dart`:

```dart
import 'agent_eval_failure.dart';

class AgentEvalAssertionResult {
  const AgentEvalAssertionResult({
    required this.kind,
    required this.passed,
    required this.reason,
  });

  final String kind;
  final bool passed;
  final String reason;

  Map<String, Object?> toJson() => {
    'kind': kind,
    'passed': passed,
    'reason': reason,
  };
}

class AgentEvalResult {
  const AgentEvalResult({
    required this.caseId,
    required this.success,
    required this.failureKind,
    required this.finalResult,
    required this.steps,
    required this.duration,
    required this.assertions,
  });

  final String caseId;
  final bool success;
  final AgentEvalFailureKind? failureKind;
  final String finalResult;
  final int steps;
  final Duration duration;
  final List<AgentEvalAssertionResult> assertions;

  Map<String, Object?> toJson() => {
    'caseId': caseId,
    'success': success,
    'failureKind': failureKind?.name,
    'finalResult': finalResult,
    'steps': steps,
    'durationMs': duration.inMilliseconds,
    'assertions': assertions.map((a) => a.toJson()).toList(),
  };
}
```

- [ ] **Step 4: Implement case and assertion types**

Create `test/phone_agent_eval/agent_eval_case.dart`:

```dart
import 'package:scrcpy_client/scrcpy_client.dart';
import 'package:scrcpy_mcp/scrcpy_mcp.dart';

import 'agent_eval_result.dart';

class AgentEvalCase {
  const AgentEvalCase({
    required this.id,
    required this.description,
    required this.task,
    required this.config,
    this.setup,
    required this.assertions,
  });

  final String id;
  final String description;
  final String task;
  final AgentConfig config;
  final Future<void> Function(AgentEvalDevice device)? setup;
  final List<AgentEvalAssertion> assertions;
}

class AgentEvalDevice {
  const AgentEvalDevice({
    required this.adb,
    required this.deviceId,
  });

  final ScrcpyAdb adb;
  final String deviceId;

  Future<void> pressHome() async {
    await adb.shell(['input', 'keyevent', 'KEYCODE_HOME'], deviceId: deviceId);
  }

  Future<void> pressBack() async {
    await adb.shell(['input', 'keyevent', 'KEYCODE_BACK'], deviceId: deviceId);
  }

  Future<void> launchPackage(String packageName) async {
    await adb.shell([
      'monkey',
      '-p',
      packageName,
      '-c',
      'android.intent.category.LAUNCHER',
      '1',
    ], deviceId: deviceId);
  }

  Future<void> waitFor(Duration duration) => Future<void>.delayed(duration);
}

sealed class AgentEvalAssertion {
  const AgentEvalAssertion();
}

final class TextContainsAssertion extends AgentEvalAssertion {
  const TextContainsAssertion(this.expected);

  final String expected;

  AgentEvalAssertionResult evaluateText(String finalResult) {
    final passed = finalResult.contains(expected);
    return AgentEvalAssertionResult(
      kind: 'text_contains',
      passed: passed,
      reason: passed
          ? 'Final result contains "$expected".'
          : 'Expected final result to contain "$expected".',
    );
  }
}

final class VisualContainsAssertion extends AgentEvalAssertion {
  const VisualContainsAssertion(this.expectation);

  final String expectation;
}
```

- [ ] **Step 5: Run model tests**

Run:

```bash
dart test test/phone_agent_eval/agent_eval_test.dart
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add test/phone_agent_eval/agent_eval_case.dart test/phone_agent_eval/agent_eval_result.dart test/phone_agent_eval/agent_eval_test.dart
git commit -m "test(agent-eval): add eval result models"
```

## Task 3: Eval Runner and Artifacts

**Files:**
- Create: `test/phone_agent_eval/agent_eval_runner.dart`
- Modify: `test/phone_agent_eval/agent_eval_test.dart`

- [ ] **Step 1: Add failing runner test**

Append imports to `test/phone_agent_eval/agent_eval_test.dart`:

```dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:scrcpy_mcp/scrcpy_mcp.dart';
```

Also import:

```dart
import 'agent_eval_runner.dart';
```

Append this fake and group:

```dart
class _FakeEvalActionRunner {
  final actions = <DoAction>[];

  Future<String> call(DoAction action) async {
    actions.add(action);
    return 'ran ${action.action}';
  }
}

void _expectFileExists(String path) {
  expect(File(path).existsSync(), isTrue, reason: '$path should exist');
}
```

Inside `main()` append:

```dart
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
```

Add `_ArtifactAdb` after `_FakeEvalActionRunner`:

```dart
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
  Future<void> push(String localPath, String remotePath, {String? deviceId}) async {}

  @override
  Future<Process> startProcess(List<String> arguments) {
    throw UnimplementedError();
  }

  @override
  Future<Uint8List> takeScreenshot(String deviceId) async =>
      Uint8List.fromList([1]);
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
dart test test/phone_agent_eval/agent_eval_test.dart
```

Expected: FAIL because `AgentEvalRunner` is missing.

- [ ] **Step 3: Implement runner**

Create `test/phone_agent_eval/agent_eval_runner.dart`:

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:scrcpy_mcp/scrcpy_mcp.dart';

import '../phone_agent_test/utils/visual_assertion.dart';
import 'agent_eval_case.dart';
import 'agent_eval_failure.dart';
import 'agent_eval_result.dart';

typedef EvalScreenshotProvider = Future<Uint8List> Function();

class AgentEvalRunner {
  AgentEvalRunner({
    required this.outputRoot,
    required this.deviceId,
    required this.adb,
    required this.chat,
    required this.screenshotProvider,
    required this.actionRunner,
  });

  final Directory outputRoot;
  final String deviceId;
  final ScrcpyMcpAdb adb;
  final ChatFn chat;
  final EvalScreenshotProvider screenshotProvider;
  final ActionRunner actionRunner;

  Future<AgentEvalResult> runCase(AgentEvalCase evalCase) async {
    final watch = Stopwatch()..start();
    final caseDir = Directory('${outputRoot.path}/${evalCase.id}');
    final screenshotDir = Directory('${caseDir.path}/screenshots');
    await screenshotDir.create(recursive: true);
    final stepsFile = File('${caseDir.path}/steps.jsonl');
    final sink = stepsFile.openWrite(mode: FileMode.writeOnly);
    var step = 0;

    void writeEvent(Map<String, Object?> event) {
      sink.writeln(jsonEncode(event));
    }

    try {
      if (evalCase.setup != null) {
        await evalCase.setup!(
          AgentEvalDevice(adb: adb, deviceId: deviceId),
        );
      }
    } catch (e) {
      final result = AgentEvalResult(
        caseId: evalCase.id,
        success: false,
        failureKind: AgentEvalFailureKind.toolError,
        finalResult: 'Setup failed: $e',
        steps: 0,
        duration: watch.elapsed,
        assertions: const [],
      );
      writeEvent({'type': 'final', ...result.toJson()});
      await _writeFinal(caseDir, result);
      await sink.close();
      return result;
    }

    Future<({String base64, String mimeType})> tracedScreenshot() async {
      final bytes = await screenshotProvider();
      final path = '${screenshotDir.path}/${step.toString().padLeft(3, '0')}.png';
      await File(path).writeAsBytes(bytes);
      final hash = const ListEquality<int>().hash(bytes);
      writeEvent({
        'type': 'screenshot',
        'step': step,
        'hash': hash.toString(),
        'path': 'screenshots/${step.toString().padLeft(3, '0')}.png',
      });
      return (base64: base64Encode(bytes), mimeType: 'image/png');
    }

    Future<String> tracedActionRunner(PhoneAction action) async {
      if (action case DoAction doAction) {
        final result = await actionRunner(doAction);
        writeEvent({
          'type': 'action',
          'step': step,
          'summary': doAction.action,
          'raw': doAction.toString(),
          'result': result,
        });
        step++;
        return result;
      }
      return '(finish)';
    }

    Future<LlmResponse> tracedChat({required List<LlmMessage> messages}) async {
      final response = await chat(messages: messages);
      writeEvent({
        'type': 'llm_response',
        'step': step,
        'finishReason': response.finishReason,
        'text': response.text,
      });
      return response;
    }

    AgentResult agentResult;
    try {
      final agent = PhoneAgent(
        config: evalCase.config,
        llmClient: tracedChat,
        takeScreenshot: tracedScreenshot,
        actionRunner: tracedActionRunner,
      );
      agentResult = await agent.run(evalCase.task);
    } catch (e) {
      final result = AgentEvalResult(
        caseId: evalCase.id,
        success: false,
        failureKind: AgentEvalFailureKind.toolError,
        finalResult: e.toString(),
        steps: step,
        duration: watch.elapsed,
        assertions: const [],
      );
      writeEvent({'type': 'final', ...result.toJson()});
      await _writeFinal(caseDir, result);
      await sink.close();
      return result;
    }

    final assertionResults = <AgentEvalAssertionResult>[];
    AgentEvalFailureKind? assertionFailure;
    for (final assertion in evalCase.assertions) {
      final assertionResult = await _evaluateAssertion(assertion, agentResult);
      assertionResults.add(assertionResult);
      writeEvent({
        'type': 'assertion',
        ...assertionResult.toJson(),
      });
      if (!assertionResult.passed) {
        assertionFailure ??= assertion is VisualContainsAssertion
            ? AgentEvalFailureKind.visualAssertionFailed
            : AgentEvalFailureKind.textAssertionFailed;
      }
    }

    final failureKind = agentResult.success
        ? assertionFailure
        : classifyAgentFailure(agentResult.result);
    final result = AgentEvalResult(
      caseId: evalCase.id,
      success: agentResult.success && assertionFailure == null,
      failureKind: failureKind,
      finalResult: agentResult.result,
      steps: agentResult.steps,
      duration: watch.elapsed,
      assertions: assertionResults,
    );
    writeEvent({'type': 'final', ...result.toJson()});
    await _writeFinal(caseDir, result);
    await sink.close();
    return result;
  }

  Future<AgentEvalAssertionResult> _evaluateAssertion(
    AgentEvalAssertion assertion,
    AgentResult agentResult,
  ) async {
    switch (assertion) {
      case TextContainsAssertion():
        return assertion.evaluateText(agentResult.result);
      case VisualContainsAssertion(:final expectation):
        try {
          final check = await checkDeviceScreenContains(
            chat: chat,
            adb: adb,
            deviceId: deviceId,
            expectation: expectation,
          );
          return AgentEvalAssertionResult(
            kind: 'visual_contains',
            passed: check.matched,
            reason: check.reason,
          );
        } catch (e) {
          return AgentEvalAssertionResult(
            kind: 'visual_contains',
            passed: false,
            reason: e.toString(),
          );
        }
    }
  }

  Future<void> _writeFinal(Directory caseDir, AgentEvalResult result) async {
    await File('${caseDir.path}/result.json').writeAsString(
      const JsonEncoder.withIndent('  ').convert(result.toJson()),
    );
    await File('${caseDir.path}/final.txt').writeAsString(result.finalResult);
  }
}
```

- [ ] **Step 4: Run runner tests**

Run:

```bash
dart test test/phone_agent_eval/agent_eval_test.dart
```

Expected: PASS.

- [ ] **Step 5: Format eval files**

Run:

```bash
dart format test/phone_agent_eval
```

Expected: files formatted with no errors.

- [ ] **Step 6: Commit**

```bash
git add test/phone_agent_eval
git commit -m "test(agent-eval): write eval artifacts"
```

## Task 4: Real-Device Eval Cases

**Files:**
- Create: `test/phone_agent_eval/cases/settings_navigation.dart`
- Create: `test/phone_agent_eval/cases/twitter_home.dart`
- Create: `test/phone_agent_eval/cases/youtube_history_recent.dart`
- Create: `test/phone_agent_eval/agent_eval_real_device_test.dart`

- [ ] **Step 1: Create settings case**

Create `test/phone_agent_eval/cases/settings_navigation.dart`:

```dart
import 'package:scrcpy_mcp/scrcpy_mcp.dart';

import '../agent_eval_case.dart';

const settingsNavigationCase = AgentEvalCase(
  id: 'settings_navigation',
  description: 'Open Android Settings and verify the settings UI is visible.',
  task: '''
请打开 Android 系统设置页面。完成后用 finish(message="done") 返回。
''',
  config: AgentConfig(maxSteps: 10),
  assertions: [VisualContainsAssertion('Android 系统设置页面')],
);
```

- [ ] **Step 2: Create Twitter case**

Create `test/phone_agent_eval/cases/twitter_home.dart`:

```dart
import 'package:scrcpy_mcp/scrcpy_mcp.dart';

import '../agent_eval_case.dart';

const twitterHomeCase = AgentEvalCase(
  id: 'twitter_home',
  description: 'Open Twitter/X homepage through Chrome and verify it is visible.',
  task: '''
帮我通过 Chrome 打开 Twitter/X 官网，网址是 https://www.x.com。
如果不在主页，先按 HOME。打开后等待页面加载，并确认当前页面是 Twitter/X 主页。
完成后用 finish(message="done") 返回。
''',
  config: AgentConfig(maxSteps: 12),
  assertions: [VisualContainsAssertion('Twitter（X）的主页')],
);
```

- [ ] **Step 3: Create YouTube history case**

Create `test/phone_agent_eval/cases/youtube_history_recent.dart`:

```dart
import 'package:scrcpy_mcp/scrcpy_mcp.dart';

import '../agent_eval_case.dart';

const youtubeHistoryRecentCase = AgentEvalCase(
  id: 'youtube_history_recent',
  description: 'Navigate to YouTube history and summarize recent visible videos.',
  task: '''
打开 YouTube 的历史记录页面，读取当前屏幕可见的最近视频条目。
不要点击视频条目，避免进入播放页。只需要总结当前可见的 2 到 3 个视频标题或频道信息。
完成后用 finish(message="...") 返回总结。
''',
  config: AgentConfig(maxSteps: 25, repeatedActionThreshold: 8),
  assertions: [
    TextContainsAssertion('视频'),
    VisualContainsAssertion('YouTube 历史记录页面'),
  ],
);
```

- [ ] **Step 4: Add gated real-device eval suite**

Create `test/phone_agent_eval/agent_eval_real_device_test.dart`:

```dart
@Tags(['real-device'])
library;

import 'dart:io';

import 'package:adb_tools/adb_tools.dart';
import 'package:logger_utils/logger_utils.dart';
import 'package:scrcpy_mcp/scrcpy_mcp.dart';
import 'package:scrcpy_mcp/src/agent/adb_action_runner.dart';
import 'package:test/test.dart';

import 'agent_eval_runner.dart';
import 'cases/settings_navigation.dart';
import 'cases/twitter_home.dart';
import 'cases/youtube_history_recent.dart';

void main() {
  initLogging();

  test('real-device agent eval cases', () async {
    if (Platform.environment['SCRCPY_RUN_AGENT_EVAL'] != '1') {
      markTestSkipped('Set SCRCPY_RUN_AGENT_EVAL=1 to run agent eval cases.');
      return;
    }
    if (Platform.environment['AUTOGLM_BASE_URL'] == null ||
        Platform.environment['AUTOGLM_API_KEY'] == null ||
        Platform.environment['AUTOGLM_MODEL'] == null) {
      markTestSkipped('AUTOGLM_BASE_URL/API_KEY/MODEL env vars are required.');
      return;
    }

    final adbClient = AdbClient();
    final adb = ScrcpyMcpAdb(adbClient);
    final devices = await adb.getDevices();
    if (devices.isEmpty) {
      markTestSkipped('No Android device connected via ADB.');
      return;
    }
    final deviceId = devices.first;
    final deviceInfo = await adbClient.getDeviceInfo(deviceId);
    final actionRunner = AdbActionRunner(
      adb: adb,
      deviceId: deviceId,
      size: (deviceInfo.screenWidth, deviceInfo.screenHeight),
    );
    final runner = AgentEvalRunner(
      outputRoot: Directory(
        'temp/agent_eval_runs/${DateTime.now().toIso8601String()}',
      ),
      deviceId: deviceId,
      adb: adb,
      chat: AutoGLMClient.fromEnv().chat,
      screenshotProvider: () => adb.takeScreenshot(deviceId),
      actionRunner: actionRunner.run,
    );

    final cases = [
      settingsNavigationCase,
      twitterHomeCase,
      youtubeHistoryRecentCase,
    ];
    final results = <AgentEvalResult>[];
    for (final evalCase in cases) {
      results.add(await runner.runCase(evalCase));
    }

    expect(
      results.where((result) => !result.success),
      isEmpty,
      reason: results
          .map((r) => '${r.caseId}: ${r.success} ${r.failureKind} ${r.finalResult}')
          .join('\n'),
    );
  }, timeout: const Timeout(Duration(minutes: 15)));
}
```

- [ ] **Step 5: Run unit tests**

Run:

```bash
dart test test/phone_agent_eval/agent_eval_test.dart
```

Expected: PASS.

- [ ] **Step 6: Run gated real-device test without env**

Run:

```bash
dart test test/phone_agent_eval/agent_eval_real_device_test.dart
```

Expected: test is skipped with message about `SCRCPY_RUN_AGENT_EVAL=1`.

- [ ] **Step 7: Format eval files**

Run:

```bash
dart format test/phone_agent_eval
```

Expected: files formatted with no errors.

- [ ] **Step 8: Commit**

```bash
git add test/phone_agent_eval
git commit -m "test(agent-eval): add real-device eval cases"
```

## Task 5: Final Verification

**Files:**
- Review: `docs/superpowers/specs/2026-06-08-agent-eval-harness-design.md`
- Review: `test/phone_agent_eval/**`

- [ ] **Step 1: Run eval unit tests**

Run:

```bash
dart test test/phone_agent_eval/agent_eval_test.dart
```

Expected: PASS.

- [ ] **Step 2: Run real-device eval gate test without env**

Run:

```bash
dart test test/phone_agent_eval/agent_eval_real_device_test.dart
```

Expected: skipped when `SCRCPY_RUN_AGENT_EVAL` is not set.

- [ ] **Step 3: Run analyzer on touched test files**

Run:

```bash
dart analyze test/phone_agent_eval
```

Expected: no issues.

- [ ] **Step 4: Confirm git status**

Run:

```bash
git status --short
```

Expected: clean except unrelated pre-existing untracked `package.json` and `package-lock.json` if they are still present.

- [ ] **Step 5: Commit any final formatting or analyzer fixes**

If Task 5 changes files:

```bash
git add test/phone_agent_eval
git commit -m "test(agent-eval): polish eval harness"
```

If no files changed, no commit is needed.
