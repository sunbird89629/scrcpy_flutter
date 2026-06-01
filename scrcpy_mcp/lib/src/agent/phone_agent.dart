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
    final messages = <LlmMessage>[
      LlmMessage(role: 'system', textContent: config.systemPrompt),
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

      final response = await llmClient.chat(messages: List.unmodifiable(messages));

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
        // Could not parse an action — treat as finish with raw text
        final cleaned = rawText
            .replaceAll(RegExp('</?think>'), '')
            .trim();
        return AgentResult(
          result: cleaned,
          steps: step + 1,
          success: true,
        );
      }

      // 4. Add assistant response to history
      messages.add(LlmMessage(role: 'assistant', textContent: rawText));

      switch (action) {
        case DoAction():
          String result;
          try {
            result = await actionRunner(action);
          } catch (e) {
            result = 'Error executing $action: $e';
          }
          // Result will show in next step's screenshot — no tool message needed
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
}
