import 'dart:convert';

import 'agent_config.dart';
import 'llm_client.dart';

/// Callback that executes one tool call and returns text + optional image.
typedef ToolExecutor = Future<
    ({String text, String? imageBase64, String? imageMimeType})> Function(
  String name,
  Map<String, dynamic> args,
);

/// ReAct agent: loops think → act → observe until the LLM stops calling tools
/// or [AgentConfig.maxSteps] is exhausted.
class PhoneAgent {
  const PhoneAgent({
    required this.config,
    required this.llmClient,
    required this.tools,
    required this.executeToolCall,
  });

  final AgentConfig config;
  final LlmClient llmClient;
  final List<ToolSchema> tools;
  final ToolExecutor executeToolCall;

  Future<AgentResult> run(String message) async {
    final messages = <LlmMessage>[
      LlmMessage(role: 'system', textContent: config.systemPrompt),
      LlmMessage(role: 'user', textContent: message),
    ];

    for (var step = 0; step < config.maxSteps; step++) {
      final response = await llmClient.chat(messages: messages, tools: tools);

      if (!response.isToolCall) {
        return AgentResult(
          result: response.text ?? '',
          steps: step + 1,
          success: true,
        );
      }

      // Append assistant's tool-call message
      messages.add(LlmMessage(
        role: 'assistant',
        toolCalls: response.toolCalls,
      ));

      // Execute each tool call, append result
      for (final call in response.toolCalls!) {
        final result = await _safeExecute(call);
        messages.add(LlmMessage(
          role: 'tool',
          textContent: result.text,
          imageBase64: result.imageBase64,
          imageMimeType: result.imageMimeType,
          toolCallId: call.id,
        ));
      }
    }

    return AgentResult(
      result:
          'Max steps (${config.maxSteps}) reached without completing the task.',
      steps: config.maxSteps,
      success: false,
    );
  }

  Future<({String text, String? imageBase64, String? imageMimeType})>
      _safeExecute(ToolCall call) async {
    try {
      final args = jsonDecode(call.arguments) as Map<String, dynamic>;
      return await executeToolCall(call.name, args);
    } catch (e) {
      return (text: 'Error: $e', imageBase64: null, imageMimeType: null);
    }
  }
}
