import 'package:logger_utils/logger_utils.dart';

import '../clients/agent_model_client.dart';
import '../clients/llm_client.dart';
import 'sop_record.dart';

final _log = Logger('scrcpy.mcp.sop.retriever');

/// Picks the SOP records most relevant to a task, using the model to rank
/// candidate intents. Returns [] when there are no candidates.
class SopRetriever {
  SopRetriever(this._client);

  final AgentModelClient _client;

  Future<List<SopRecord>> select({
    required String taskText,
    required List<SopRecord> candidates,
    int limit = 3,
  }) async {
    if (candidates.isEmpty) return const [];
    final list = [
      for (var i = 0; i < candidates.length; i++)
        '$i. [${candidates[i].polarity.name}] ${candidates[i].intent}',
    ].join('\n');
    final prompt =
        '任务：$taskText\n\n已有经验（编号. [类型] 意图）：\n$list\n\n'
        '只输出与该任务相关的编号，用逗号分隔；都不相关则输出 none。';
    final resp = await _client.chat(
      messages: [LlmMessage(role: 'user', textContent: prompt)],
    );
    final text = resp.text ?? '';
    final picked = <SopRecord>[];
    for (final m in RegExp(r'\d+').allMatches(text)) {
      final idx = int.parse(m.group(0)!);
      if (idx >= 0 && idx < candidates.length) picked.add(candidates[idx]);
      if (picked.length >= limit) break;
    }
    _log.info('retrieved ${picked.length}/${candidates.length} SOP(s)');
    return picked;
  }
}
