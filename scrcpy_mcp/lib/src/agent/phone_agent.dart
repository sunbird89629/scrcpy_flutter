import 'package:collection/collection.dart';
import 'package:logger_utils/logger_utils.dart';

import 'action_parser.dart';
import 'agent_config.dart';
import 'llm_client.dart';

final _log = Logger('PhoneAgent');

/// Callback that takes a screenshot and returns base64-encoded PNG data.
typedef ScreenshotProvider =
    Future<({String base64, String mimeType})> Function();

/// Callback that executes one [PhoneAction] on the device.
typedef ActionRunner = Future<String> Function(PhoneAction action);

/// Multimodal ReAct agent for autoglm-phone.
///
/// On each step:
///   1. Take a screenshot
///   2. Send [system + user(message+screenshot) + history] to the LLM
///   3. Parse the model's text output with [ActionParser]
///   4. Execute parsed [DoAction] via [actionRunner], or finish
///   5. Append to history and loop
class PhoneAgent {
  const PhoneAgent({
    required this.config,
    required this.llmClient,
    required this.takeScreenshot,
    required this.actionRunner,
  });

  final AgentConfig config;
  final LlmClient llmClient;
  final ScreenshotProvider takeScreenshot;
  final ActionRunner actionRunner;

  static const _weekdayNames = [
    '星期一',
    '星期二',
    '星期三',
    '星期四',
    '星期五',
    '星期六',
    '星期日',
  ];

  Future<AgentResult> run(String message) async {
    final now = DateTime.now();
    final mm = now.month.toString().padLeft(2, '0');
    final dd = now.day.toString().padLeft(2, '0');
    final weekday = _weekdayNames[now.weekday - 1];
    final dateStr = '${now.year}年$mm月$dd日 $weekday';
    final systemPrompt = config.systemPrompt.replaceFirst('{DATE}', dateStr);

    final messages = MessageList(<LlmMessage>[
      LlmMessage(role: 'system', textContent: systemPrompt),
    ]);

    String? prevScreenshot;
    var stalledSteps = 0;
    String? lastResult;

    for (var step = 0; step < config.maxSteps; step++) {
      // 1. Take screenshot
      final screenshot = await takeScreenshot();

      // Stall backstop: if the screen is unchanged across consecutive steps,
      // the actions are having no effect. Abort instead of burning steps/tokens
      // re-asking the model (which often keeps guessing). Mirrors the prompt's
      // own "连续3次操作后界面没有变化" rule, which the model tends to ignore.
      if (prevScreenshot != null && screenshot.base64 == prevScreenshot) {
        stalledSteps++;
      } else {
        stalledSteps = 0;
      }
      prevScreenshot = screenshot.base64;
      if (stalledSteps >= config.stallThreshold) {
        return AgentResult(
          result:
              'Aborted: screen unchanged for ${stalledSteps + 1} consecutive '
              'steps — actions are having no visible effect.',
          steps: step + 1,
          success: false,
        );
      }

      // Feed the previous action's result back instead of a constant prompt.
      // This gives the model outcome feedback to self-correct, and — because the
      // text varies each step — avoids the low-temperature repetition collapse
      // that a fixed "继续执行任务" can trigger.
      final userContent = step == 0
          ? message
          : '上一步操作结果：${lastResult ?? '已执行'}。请对照当前截图判断是否生效，并继续完成任务。';

      final llmMessage = LlmMessage(
        role: 'user',
        textContent: userContent,
        imageBase64: screenshot.base64,
        imageMimeType: screenshot.mimeType,
      );
      // 2. Send to LLM with screenshot
      messages.add(llmMessage);
      final response = await llmClient.chat(messages: _trimHistory(messages));

      final rawText = response.text ?? '';
      _log.info('rawText:$rawText');

      if (rawText.isEmpty) {
        return AgentResult(
          result: 'Model returned empty response at step $step',
          steps: step + 1,
          success: false,
        );
      }

      // 3. Parse action from model output
      final action = ActionParser.parse(rawText);

      if (action == null) {
        // The model must emit a parseable action — completion goes through
        // finish(...)/screenshot(...), which ActionParser handles. Reaching
        // here means the output format broke, so report failure instead of
        // masquerading a format error as success.
        final cleaned = rawText.replaceAll(RegExp('</?think>'), '').trim();
        return AgentResult(
          result: 'Could not parse an action from model output: $cleaned',
          steps: step + 1,
          success: false,
        );
      }

      // 4. Add assistant response to history
      final assistantMessage = LlmMessage(
        role: 'assistant',
        textContent: rawText,
      );
      messages.add(assistantMessage);

      switch (action) {
        case DoAction():
          // Take_over (login/verification) and Interact (ambiguous choice) both
          // need a human in the loop, which a headless run_task does not have —
          // abort with the model's message rather than guess.
          if (action.action == 'Take_over' || action.action == 'Interact') {
            return AgentResult(
              result: 'Task requires human: ${action.message ?? action.action}',
              steps: step + 1,
              success: false,
            );
          }

          String result;
          try {
            result = await actionRunner(action);
          } catch (e) {
            result = 'Error executing $action: $e';
          }
          lastResult = result;
          if (step == config.maxSteps - 1) {
            return AgentResult(
              result: 'Max steps reached after executing: $action → $result',
              steps: step + 1,
              success: false,
            );
          }

        case FinishAction():
          return AgentResult(
            result: action.message,
            steps: step + 1,
            success: true,
          );
      }
    }

    return AgentResult(
      result:
          'Max steps (${config.maxSteps}) reached without completing the task.',
      steps: config.maxSteps,
      success: false,
    );
  }

  /// Returns a copy of [messages] keeping only the [AgentConfig.keepScreenshots]
  /// most recent screenshots. autoglm-phone has a 20K-token context window and
  /// each full-screen screenshot costs ~1–1.5K tokens, so retaining every
  /// step's image would overflow the window and eventually evict the system
  /// prompt. Keeping the last few (not just one) lets the model compare recent
  /// frames to notice a stalled screen; older images are dropped but their text
  /// is preserved.
  List<LlmMessage> _trimHistory(List<LlmMessage> messages) {
    final keep = config.keepScreenshots;

    // Indices of image-bearing messages, newest first.
    final imageIndices = <int>[];
    for (var i = messages.length - 1; i >= 0; i--) {
      if (messages[i].imageBase64 != null) imageIndices.add(i);
    }
    if (imageIndices.length <= keep) return List.unmodifiable(messages);

    final keepSet = imageIndices.take(keep).toSet();
    return List.unmodifiable([
      for (var i = 0; i < messages.length; i++)
        if (messages[i].imageBase64 == null || keepSet.contains(i))
          messages[i]
        else
          LlmMessage(
            role: messages[i].role,
            textContent: messages[i].textContent == null
                ? '（历史截图已省略）'
                : '${messages[i].textContent}\n（历史截图已省略）',
          ),
    ]);
  }
}

class MessageList extends DelegatingList<LlmMessage> {
  MessageList(super.base);
  @override
  void add(LlmMessage value) {
    _log.info(value.toLog());
    super.add(value);
  }
}
