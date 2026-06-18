import 'dart:convert';

import 'package:logger_utils/logger_utils.dart';

import '../agent_model_client.dart';
import '../llm_client.dart';
import 'sop_record.dart';
import 'sop_store.dart';

final _log = Logger('scrcpy.mcp.sop.writer');

/// Summarizes a finished run's trajectory into one SOP record and stores it.
class SopWriter {
  SopWriter(this._client, this._store);

  final AgentModelClient _client;
  final SopStore _store;

  Future<void> write({
    required String package,
    required String taskText,
    required bool success,
    required List<String> trajectory,
    String? deviceHint,
  }) async {
    final outcome = success ? '成功' : '失败';
    final pitfall = success ? 'null（成功可为 null）' : '失败的关键坑点';
    final prompt =
        '任务：$taskText\n执行结果：$outcome\n动作轨迹：\n${trajectory.join('\n')}\n\n'
        '请总结成 JSON：{"intent":"意图标题","steps":["意图级步骤"],"pitfall":"$pitfall"}。只输出 JSON。';
    final resp = await _client.chat(
      messages: [LlmMessage(role: 'user', textContent: prompt)],
    );
    final parsed = _extractJson(resp.text ?? '');
    if (parsed == null) {
      _log.warning('SOP summary not parseable; skip write');
      return;
    }
    final record = SopRecord(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      package: package,
      intent: parsed['intent'] as String? ?? taskText,
      polarity: success ? SopPolarity.positive : SopPolarity.negative,
      steps: (parsed['steps'] as List?)?.cast<String>() ?? const [],
      pitfall: parsed['pitfall'] as String?,
      sourceTask: taskText,
      createdAt: DateTime.now().toUtc(),
      deviceHint: deviceHint,
    );
    await _store.append(record);
    _log.info(
      'wrote ${record.polarity.name} SOP for $package: ${record.intent}',
    );
  }

  Map<String, dynamic>? _extractJson(String text) {
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start < 0 || end <= start) return null;
    try {
      return jsonDecode(text.substring(start, end + 1)) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }
}
