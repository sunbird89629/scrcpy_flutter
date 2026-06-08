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

  (int, int)? _screenSize;

  Future<(int, int)> _getScreenSize() async {
    if (_screenSize != null) return _screenSize!;
    final result = await adb.shell(['wm', 'size'], deviceId: deviceId);
    final m = RegExp(
      r'(\d+)x(\d+)',
    ).firstMatch((result.stdout as String).trim());
    if (m != null) {
      _screenSize = (int.parse(m.group(1)!), int.parse(m.group(2)!));
    }
    return _screenSize ?? (1080, 2340);
  }

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
        await evalCase.setup!(AgentEvalDevice(adb: adb, deviceId: deviceId));
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
      final path =
          '${screenshotDir.path}/${step.toString().padLeft(3, '0')}.png';
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
      if (action case final DoAction doAction) {
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
      final size = await _getScreenSize();
      final config = AgentConfig(
        maxSteps: evalCase.config.maxSteps,
        systemPrompt: evalCase.config.systemPrompt,
        keepScreenshots: evalCase.config.keepScreenshots,
        stallThreshold: evalCase.config.stallThreshold,
        repeatedActionThreshold: evalCase.config.repeatedActionThreshold,
        screenSize: size,
      );
      final agent = PhoneAgent(
        config: config,
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
      writeEvent({'type': 'assertion', ...assertionResult.toJson()});
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

    try {
      await evalCase.teardown?.call(
        AgentEvalDevice(adb: adb, deviceId: deviceId),
      );
    } catch (_) {
      // Teardown failures should not affect the eval result.
    }

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
