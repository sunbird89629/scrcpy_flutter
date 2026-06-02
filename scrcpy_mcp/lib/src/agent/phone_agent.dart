import 'action_parser.dart';
import 'agent_config.dart';
import 'llm_client.dart';

/// Callback that takes a screenshot and returns base64-encoded PNG data.
typedef ScreenshotProvider = Future<({String base64, String mimeType})>
Function();

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

  Future<AgentResult> run(String message) async {
    final dateStr =
        '${DateTime.now().year}年${DateTime.now().month}月${DateTime.now().day}日';
    final systemPrompt = config.systemPrompt.replaceFirst('{DATE}', dateStr);
    final messages = <LlmMessage>[
      LlmMessage(role: 'system', textContent: systemPrompt),
    ];

    for (var step = 0; step < config.maxSteps; step++) {
      // 1. Take screenshot
      final screenshot = await takeScreenshot();
      final userContent = step == 0 ? message : '继续执行任务';

      // 2. Send to LLM with screenshot
      messages.add(
        LlmMessage(
          role: 'user',
          textContent: userContent,
          imageBase64: screenshot.base64,
          imageMimeType: screenshot.mimeType,
        ),
      );

      final response = await llmClient.chat(messages: _trimHistory(messages));

      final rawText = response.text ?? '';
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
        final cleaned = rawText
            .replaceAll(RegExp('</?think>'), '')
            .trim();
        return AgentResult(
          result: 'Could not parse an action from model output: $cleaned',
          steps: step + 1,
          success: false,
        );
      }

      // 4. Add assistant response to history
      messages.add(LlmMessage(role: 'assistant', textContent: rawText));

      switch (action) {
        case DoAction():
          // Take_over means the task cannot continue without human help.
          if (action.action == 'Take_over') {
            return AgentResult(
              result: 'Task requires human: ${action.message ?? ""}',
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
      result: 'Max steps (${config.maxSteps}) reached without completing the task.',
      steps: config.maxSteps,
      success: false,
    );
  }

  /// Returns a copy of [messages] where only the most recent screenshot is
  /// kept. autoglm-phone has a 20K-token context window and each full-screen
  /// screenshot costs ~1–1.5K tokens, so retaining every step's image would
  /// overflow the window within a handful of steps and eventually evict the
  /// system prompt. The model decides from the current screen plus the textual
  /// action history (the assistant turns), so stale screenshots only waste
  /// tokens — drop them but keep their text.
  static List<LlmMessage> _trimHistory(List<LlmMessage> messages) {
    var lastImageIndex = -1;
    for (var i = messages.length - 1; i >= 0; i--) {
      if (messages[i].imageBase64 != null) {
        lastImageIndex = i;
        break;
      }
    }
    if (lastImageIndex == -1) return List.unmodifiable(messages);

    return List.unmodifiable([
      for (var i = 0; i < messages.length; i++)
        if (i == lastImageIndex || messages[i].imageBase64 == null)
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
