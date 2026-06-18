import 'package:logger_utils/logger_utils.dart';

import 'action_summary.dart';
import 'agent_config.dart';
import 'agent_model_client.dart';
import 'llm_client.dart';
import 'response_parser.dart';

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
///   3. Parse the model's text output with [ResponseParser]
///   4. Execute parsed [DoAction] via [actionRunner], or finish
///   5. Append to history and loop
class PhoneAgent {
  const PhoneAgent({
    required this.config,
    required this.client,
    required this.takeScreenshot,
    required this.actionRunner,
  });

  final AgentConfig config;
  final AgentModelClient client;
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
    _log.info('task: $message');
    final messages = _buildInitialMessages();
    final memories = <String>[];

    String? prevScreenshot;
    var stalledSteps = 0;
    String? lastResult;
    String? lastActionSig;
    var repeatedActions = 0;

    for (var step = 0; step < config.maxSteps; step++) {
      // 1. Take screenshot, then check the stall backstop.
      final screenshot = await takeScreenshot();
      if (prevScreenshot != null && screenshot.base64 == prevScreenshot) {
        stalledSteps++;
      } else {
        stalledSteps = 0;
      }
      prevScreenshot = screenshot.base64;
      final stall = _stallAbort(stalledSteps, step);
      if (stall != null) {
        _log.warning(stall.result);
        return stall;
      }

      // 2. Ask the model for the next action (handles truncation retry).
      final userContent = _buildUserContent(
        step,
        message,
        lastResult,
        memories,
      );
      final parsed = await _requestAction(
        messages,
        userContent: userContent,
        screenshot: screenshot,
      );

      switch (parsed) {
        case ParseFailure(:final reason, :final content):
          // Completion goes through finish(...), which the parser recognizes.
          // A failure here means the output format broke — report it rather
          // than masquerading a format error as success.
          _log.warning('step $step parse failed: $reason');
          return AgentResult(
            result: 'Could not parse an action ($reason): ${content.trim()}',
            steps: step + 1,
            success: false,
          );
        case ParsedAction(:final action, :final content, :final memory):
          _log.info('step $step  ${actionSummary(action)}');
          _log.fine('reply:\n${_indent(content)}');
          // Record the assistant turn, keeping only the executable action call —
          // strips any prose the model (e.g. hosted autoglm-phone) emits before
          // the do()/finish() call.
          messages.add(
            LlmMessage(role: 'assistant', textContent: _actionLine(content)),
          );
          if (client.memoryEnabled && memory.isNotEmpty) memories.add(memory);
          final outcome = await _dispatchAction(
            action,
            step,
            lastActionSig: lastActionSig,
            repeatedActions: repeatedActions,
          );
          final resultText =
              outcome.done?.result ?? outcome.result ?? '(no result)';
          _log.info('step $step → $resultText');
          if (outcome.done != null) return outcome.done!;
          lastResult = outcome.result;
          lastActionSig = outcome.sig;
          repeatedActions = outcome.repeats;
      }
    }

    final exhausted = AgentResult(
      result:
          'Max steps (${config.maxSteps}) reached without completing the task.',
      steps: config.maxSteps,
      success: false,
    );
    _log.warning(exhausted.result);
    return exhausted;
  }

  /// Builds the initial message list: a single system message with today's date
  /// and screen size substituted into the client's `systemPromptTemplate`.
  List<LlmMessage> _buildInitialMessages() {
    final now = DateTime.now();
    final mm = now.month.toString().padLeft(2, '0');
    final dd = now.day.toString().padLeft(2, '0');
    final weekday = _weekdayNames[now.weekday - 1];
    final dateStr = '${now.year}年$mm月$dd日 $weekday';
    var systemPrompt = client.systemPromptTemplate.replaceFirst(
      '{DATE}',
      dateStr,
    );
    final size = config.screenSize;
    systemPrompt = systemPrompt.replaceFirst(
      '{SCREEN_SIZE}',
      size != null ? '${size.$1}x${size.$2}' : '未知',
    );
    return <LlmMessage>[LlmMessage(role: 'system', textContent: systemPrompt)];
  }

  /// Stall backstop: if the screen is unchanged across consecutive steps, the
  /// actions are having no effect. Abort instead of burning steps/tokens
  /// re-asking the model (which often keeps guessing). Mirrors the prompt's own
  /// "连续3次操作后界面没有变化" rule, which the model tends to ignore. Returns the
  /// abort result, or null to keep going.
  AgentResult? _stallAbort(int stalledSteps, int step) {
    if (stalledSteps < config.stallThreshold) return null;
    return AgentResult(
      result:
          'Aborted: screen unchanged for ${stalledSteps + 1} consecutive '
          'steps — actions are having no visible effect.',
      steps: step + 1,
      success: false,
    );
  }

  /// The user turn text for [step]. Step 0 is the task itself; later steps feed
  /// the previous action's result back instead of a constant prompt. This gives
  /// the model outcome feedback to self-correct, and — because the text varies
  /// each step — avoids the low-temperature repetition collapse that a fixed
  /// "继续执行任务" can trigger.
  String _buildUserContent(
    int step,
    String message,
    String? lastResult,
    List<String> memories,
  ) {
    if (step == 0) return message;
    // Keep only the most recent entries: the cross-step memory block is rebuilt
    // every turn and otherwise grows unbounded with step count, bloating the
    // prompt and pushing autoglm into low-temperature repetition collapse.
    const keepMemories = 6;
    final recent = memories.length > keepMemories
        ? memories.sublist(memories.length - keepMemories)
        : memories;
    final memoryBlock = recent.isEmpty
        ? ''
        : '跨步记录：\n---\n${recent.join('\n---\n')}\n---\n';
    return '$memoryBlock'
        '上一步操作结果：${lastResult ?? '已执行'}。请对照当前截图判断是否生效，并继续完成任务。';
  }

  /// Sends a user turn (text + screenshot) and parses the model's reply into a
  /// [ParsedResponse]. On a truncated response (finish_reason="length", usually
  /// repetition garbage with no parsable action) it retries once asking for a
  /// single concise action before giving up. Mutates [messages] with the turns
  /// it sends.
  Future<ParsedResponse> _requestAction(
    List<LlmMessage> messages, {
    required String userContent,
    required ({String base64, String mimeType}) screenshot,
  }) async {
    messages.add(
      LlmMessage(
        role: 'user',
        textContent: userContent,
        imageBase64: screenshot.base64,
        imageMimeType: screenshot.mimeType,
      ),
    );
    final trimmedHistory = _trimHistory(messages);
    var response = await client.chat(messages: trimmedHistory);
    var parsed = ResponseParser.parse(response.text ?? '');

    if (parsed is ParseFailure && response.finishReason == 'length') {
      _log.info('output truncated (length); retrying with a concise nudge');
      messages.add(
        const LlmMessage(
          role: 'user',
          textContent:
              '上次输出过长被截断。请只输出一个动作指令（如 do(action="Tap", element=[x,y]) 或 finish(message="...")），不要输出任何多余内容。',
        ),
      );
      response = await client.chat(messages: _trimHistory(messages));
      parsed = ResponseParser.parse(response.text ?? '');
    }
    return parsed;
  }

  /// Keep only the executable action call in history — strips any prose the
  /// model (e.g. hosted autoglm-phone) emits before the do()/finish() call.
  static String _actionLine(String content) {
    final m = RegExp(r'(do\(|finish\()').firstMatch(content);
    return m == null ? content.trim() : content.substring(m.start).trim();
  }

  /// Executes [action] and reports the loop's next state. `done` non-null means
  /// the run should terminate with that result; otherwise `result`/`sig`/
  /// `repeats` are the updated carry-over state for the next step.
  Future<({AgentResult? done, String? result, String? sig, int repeats})>
  _dispatchAction(
    PhoneAction action,
    int step, {
    required String? lastActionSig,
    required int repeatedActions,
  }) async {
    switch (action) {
      case DoAction():
        // Take_over (login/verification) and Interact (ambiguous choice) both
        // need a human in the loop, which a headless run_task does not have —
        // abort with the model's message rather than guess.
        if (action.action == 'Take_over' || action.action == 'Interact') {
          return (
            done: AgentResult(
              result: 'Task requires human: ${action.message ?? action.action}',
              steps: step + 1,
              success: false,
            ),
            result: null,
            sig: lastActionSig,
            repeats: repeatedActions,
          );
        }

        // Action-repeat backstop: the screen-unchanged check misses loops where
        // the screen keeps changing but the agent never converges (e.g.
        // scrolling a long list forever with an identical Swipe). Abort when the
        // exact same action repeats too many times. The threshold is looser than
        // stallThreshold because some repetition (scrolling) is legitimate.
        final sig = _actionSignature(action);
        final repeats = sig == lastActionSig ? repeatedActions + 1 : 1;
        if (repeats >= config.repeatedActionThreshold) {
          return (
            done: AgentResult(
              result:
                  'Aborted: repeated the same action $repeats times '
                  'without completing the task: $action',
              steps: step + 1,
              success: false,
            ),
            result: null,
            sig: sig,
            repeats: repeats,
          );
        }

        String result;
        try {
          result = await actionRunner(action);
        } catch (e) {
          result = 'Error executing $action: $e';
        }
        final done = step == config.maxSteps - 1
            ? AgentResult(
                result: 'Max steps reached after executing: $action → $result',
                steps: step + 1,
                success: false,
              )
            : null;
        return (done: done, result: result, sig: sig, repeats: repeats);

      case FinishAction():
        return (
          done: AgentResult(
            result: action.message,
            steps: step + 1,
            success: true,
          ),
          result: null,
          sig: lastActionSig,
          repeats: repeatedActions,
        );
    }
  }

  /// A stable identity for a [DoAction], used to detect consecutive repeats.
  static String _actionSignature(DoAction a) =>
      '${a.action}|${a.element}|${a.start}|${a.end}|${a.text}|${a.app}'
      '|${a.duration}';

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

/// Indents every line of [text] by two spaces for the FINE `reply:` block.
String _indent(String text) =>
    text.trim().split('\n').map((line) => '  $line').join('\n');
