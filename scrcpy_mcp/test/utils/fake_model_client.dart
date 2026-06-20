import 'package:scrcpy_mcp/src/agent/clients/agent_model_client.dart';
import 'package:scrcpy_mcp/src/agent/clients/llm_client.dart';

/// Wraps a [ChatFn] as an [AgentModelClient] for PhoneAgent/RunTaskTool tests.
class FakeModelClient implements AgentModelClient {
  FakeModelClient(
    this._chat, {
    this.systemPromptTemplate = 'SYS',
    this.memoryEnabled = false,
  });

  final ChatFn _chat;

  @override
  final String systemPromptTemplate;

  @override
  final bool memoryEnabled;

  @override
  Future<LlmResponse> chat({required List<LlmMessage> messages}) =>
      _chat(messages: messages);
}
