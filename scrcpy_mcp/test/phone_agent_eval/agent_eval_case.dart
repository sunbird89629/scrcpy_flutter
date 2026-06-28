import 'package:scrcpy_client/scrcpy_client.dart';
import 'package:scrcpy_mcp/scrcpy_mcp.dart';

import 'agent_eval_result.dart';

class AgentEvalCase {
  final String id;
  final String description;
  final String task;
  final AgentConfig config;
  final Future<void> Function(AgentEvalDevice device)? setup;
  final Future<void> Function(AgentEvalDevice device)? teardown;
  final List<AgentEvalAssertion> assertions;

  const AgentEvalCase({
    required this.id,
    required this.description,
    required this.task,
    required this.config,
    this.setup,
    this.teardown,
    required this.assertions,
  });
}

class AgentEvalDevice {
  const AgentEvalDevice({required this.adb, required this.deviceId});

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

  /// Show a white dot on every tap so screenshots reveal tap locations.
  Future<void> enableShowTouches() async {
    await adb.shell([
      'settings',
      'put',
      'system',
      'show_touches',
      '1',
    ], deviceId: deviceId);
  }

  /// Hide tap indicator dots.
  Future<void> disableShowTouches() async {
    await adb.shell([
      'settings',
      'put',
      'system',
      'show_touches',
      '0',
    ], deviceId: deviceId);
  }
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
