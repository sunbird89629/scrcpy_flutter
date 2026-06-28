# SOP Memory Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 给 `run_task` agent 加一层跨 run 的任务级经验记忆（SOP）：执行前按包名检索注入，执行后把轨迹回写为正例/避坑反例。

**Architecture:** 纯视觉、零新运行时依赖。四个单职责组件（SopRecord / SopStore / SopRetriever / SopWriter）+ 一个前台包名解析 helper，由 `RunTaskTool` 编排为"检索→注入→回写"。全程 best-effort：任何环节失败只记 WARNING，不影响 `run_task`。SOP 功能由 `AgentConfig.sopDir` 是否非空控制。

**Tech Stack:** Dart，`package:scrcpy_client`（`ScrcpyAdb`），现有 `AgentModelClient` / `PhoneAgent`，`dart test`。

## Global Constraints

- 日志：每文件 `final _log = Logger('scrcpy.mcp.sop.<x>');`（`package:logger_utils`）；命中/回写走 INFO，best-effort 失败走 WARNING。禁用 `print`/`debugPrint`。
- 测试禁止 `test` 作为 workspace 包的 dev_dependency（用 SDK 的）；新测试不得碰真机、不得调真实 LLM；`dart test -x real-device` 必须全过。
- 不新增对外 MCP 工具；SOP 全部内建进 `run_task`。
- 不引入新运行时依赖（无 uuid / path 等包）。id 用时间戳生成；路径用 `'/'` 拼接（Dart IO 跨平台可用）。
- 遵循现有目录与命名：新代码放 `scrcpy_mcp/lib/src/agent/sop/`，测试放 `scrcpy_mcp/test/agent/sop/`。
- 命令均在 `scrcpy_mcp/` 目录下执行。

---

## File Structure

- Create: `lib/src/agent/sop/sop_record.dart` — `SopRecord` 数据模型 + JSON 序列化、`SopPolarity` 枚举。
- Create: `lib/src/agent/sop/sop_store.dart` — `SopStore`：按包名分文件读写 jsonl。
- Create: `lib/src/agent/sop/foreground_package.dart` — `parseForegroundPackage` 纯函数 + `foregroundPackage` adb 包装。
- Create: `lib/src/agent/sop/sop_retriever.dart` — `SopRetriever`：用 LLM 选相关 SOP。
- Create: `lib/src/agent/sop/sop_writer.dart` — `SopWriter`：轨迹总结成 SopRecord 并落库。
- Modify: `lib/src/agent/agent_config.dart` — `AgentResult` 增 `trajectory` + `copyWith`；`AgentConfig` 增 `sopDir`。
- Modify: `lib/src/agent/phone_agent.dart` — 收集 `trajectory`；`run` 增可选 `guidance` 注入。
- Modify: `lib/src/tools/run_task.dart` — 编排检索→注入→回写。
- Test: `test/agent/sop/sop_record_test.dart`、`sop_store_test.dart`、`foreground_package_test.dart`、`sop_retriever_test.dart`、`sop_writer_test.dart`；扩 `test/run_task_tool_test.dart`。

---

### Task 1: SopRecord 数据模型

**Files:**
- Create: `lib/src/agent/sop/sop_record.dart`
- Test: `test/agent/sop/sop_record_test.dart`

**Interfaces:**
- Produces: `enum SopPolarity { positive, negative }`；`class SopRecord` 字段 `id/package/intent/polarity/steps/pitfall?/sourceTask/createdAt/deviceHint?`；`Map<String,dynamic> toJson()`；`factory SopRecord.fromJson(Map<String,dynamic>)`。

- [ ] **Step 1: Write the failing test**

```dart
// test/agent/sop/sop_record_test.dart
import 'package:scrcpy_mcp/src/agent/sop/sop_record.dart';
import 'package:test/test.dart';

void main() {
  test('toJson/fromJson round-trips', () {
    final r = SopRecord(
      id: 'abc',
      package: 'com.tencent.mm',
      intent: '给联系人转账',
      polarity: SopPolarity.negative,
      steps: const ['进入聊天', '点右下 +'],
      pitfall: '先关引导蒙层',
      sourceTask: '给张三转 100',
      createdAt: DateTime.utc(2026, 6, 18, 10),
      deviceHint: '1080x2340 zh-CN',
    );
    final back = SopRecord.fromJson(r.toJson());
    expect(back.id, 'abc');
    expect(back.polarity, SopPolarity.negative);
    expect(back.steps, ['进入聊天', '点右下 +']);
    expect(back.pitfall, '先关引导蒙层');
    expect(back.createdAt, DateTime.utc(2026, 6, 18, 10));
  });

  test('fromJson defaults missing optional fields', () {
    final back = SopRecord.fromJson({
      'id': 'x',
      'package': 'p',
      'intent': 'i',
      'polarity': 'positive',
      'steps': ['a'],
      'source_task': 't',
      'created_at': '2026-06-18T10:00:00.000Z',
    });
    expect(back.polarity, SopPolarity.positive);
    expect(back.pitfall, isNull);
    expect(back.deviceHint, isNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/agent/sop/sop_record_test.dart`
Expected: FAIL — `sop_record.dart` not found / `SopRecord` undefined.

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/src/agent/sop/sop_record.dart
enum SopPolarity { positive, negative }

/// One task-level operation experience for a given app package.
class SopRecord {
  const SopRecord({
    required this.id,
    required this.package,
    required this.intent,
    required this.polarity,
    required this.steps,
    required this.sourceTask,
    required this.createdAt,
    this.pitfall,
    this.deviceHint,
  });

  final String id;
  final String package;
  final String intent;
  final SopPolarity polarity;
  final List<String> steps;
  final String sourceTask;
  final DateTime createdAt;
  final String? pitfall;
  final String? deviceHint;

  Map<String, dynamic> toJson() => {
    'id': id,
    'package': package,
    'intent': intent,
    'polarity': polarity.name,
    'steps': steps,
    'source_task': sourceTask,
    'created_at': createdAt.toIso8601String(),
    if (pitfall != null) 'pitfall': pitfall,
    if (deviceHint != null) 'device_hint': deviceHint,
  };

  factory SopRecord.fromJson(Map<String, dynamic> j) => SopRecord(
    id: j['id'] as String,
    package: j['package'] as String,
    intent: j['intent'] as String,
    polarity: SopPolarity.values.byName(j['polarity'] as String),
    steps: (j['steps'] as List).cast<String>(),
    sourceTask: j['source_task'] as String,
    createdAt: DateTime.parse(j['created_at'] as String),
    pitfall: j['pitfall'] as String?,
    deviceHint: j['device_hint'] as String?,
  );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `dart test test/agent/sop/sop_record_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/src/agent/sop/sop_record.dart test/agent/sop/sop_record_test.dart
git commit -m "feat(scrcpy_mcp): add SopRecord model for SOP memory"
```

---

### Task 2: SopStore（jsonl 读写）

**Files:**
- Create: `lib/src/agent/sop/sop_store.dart`
- Test: `test/agent/sop/sop_store_test.dart`

**Interfaces:**
- Consumes: `SopRecord` (Task 1).
- Produces: `class SopStore { SopStore(String baseDir); Future<List<SopRecord>> load(String package); Future<void> append(SopRecord record); }`。文件路径 `<baseDir>/sop/<package>.jsonl`，一行一条。坏行记 WARNING 跳过。

- [ ] **Step 1: Write the failing test**

```dart
// test/agent/sop/sop_store_test.dart
import 'dart:io';
import 'package:scrcpy_mcp/src/agent/sop/sop_record.dart';
import 'package:scrcpy_mcp/src/agent/sop/sop_store.dart';
import 'package:test/test.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('sop_test'));
  tearDown(() => dir.deleteSync(recursive: true));

  SopRecord rec(String id) => SopRecord(
    id: id,
    package: 'com.app',
    intent: 'i$id',
    polarity: SopPolarity.positive,
    steps: const ['a'],
    sourceTask: 't',
    createdAt: DateTime.utc(2026, 6, 18),
  );

  test('append then load returns records in order', () async {
    final store = SopStore(dir.path);
    await store.append(rec('1'));
    await store.append(rec('2'));
    final loaded = await store.load('com.app');
    expect(loaded.map((r) => r.id), ['1', '2']);
  });

  test('load returns empty for unknown package', () async {
    expect(await SopStore(dir.path).load('nope'), isEmpty);
  });

  test('load skips a corrupt line', () async {
    final store = SopStore(dir.path);
    await store.append(rec('1'));
    final f = File('${dir.path}/sop/com.app.jsonl');
    f.writeAsStringSync('{not json\n', mode: FileMode.append);
    await store.append(rec('2'));
    final loaded = await store.load('com.app');
    expect(loaded.map((r) => r.id), ['1', '2']);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/agent/sop/sop_store_test.dart`
Expected: FAIL — `SopStore` undefined.

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/src/agent/sop/sop_store.dart
import 'dart:convert';
import 'dart:io';

import 'package:logger_utils/logger_utils.dart';

import 'sop_record.dart';

final _log = Logger('scrcpy.mcp.sop.store');

/// Reads/writes SOP records as JSONL, one file per app package under
/// `<baseDir>/sop/<package>.jsonl`.
class SopStore {
  SopStore(this._baseDir);

  final String _baseDir;

  File _fileFor(String package) => File('$_baseDir/sop/$package.jsonl');

  Future<List<SopRecord>> load(String package) async {
    final f = _fileFor(package);
    if (!f.existsSync()) return const [];
    final out = <SopRecord>[];
    for (final line in await f.readAsLines()) {
      if (line.trim().isEmpty) continue;
      try {
        out.add(SopRecord.fromJson(jsonDecode(line) as Map<String, dynamic>));
      } catch (e) {
        _log.warning('skip corrupt SOP line in ${f.path}: $e');
      }
    }
    return out;
  }

  Future<void> append(SopRecord record) async {
    final f = _fileFor(record.package);
    await f.parent.create(recursive: true);
    await f.writeAsString(
      '${jsonEncode(record.toJson())}\n',
      mode: FileMode.append,
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `dart test test/agent/sop/sop_store_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/src/agent/sop/sop_store.dart test/agent/sop/sop_store_test.dart
git commit -m "feat(scrcpy_mcp): add SopStore jsonl persistence"
```

---

### Task 3: 前台包名解析

**Files:**
- Create: `lib/src/agent/sop/foreground_package.dart`
- Test: `test/agent/sop/foreground_package_test.dart`

**Interfaces:**
- Consumes: `ScrcpyAdb` from `package:scrcpy_client/scrcpy_client.dart`.
- Produces: `String? parseForegroundPackage(String dumpsysOutput)`；`Future<String?> foregroundPackage(ScrcpyAdb adb, String deviceId)`。

- [ ] **Step 1: Write the failing test**

```dart
// test/agent/sop/foreground_package_test.dart
import 'package:scrcpy_mcp/src/agent/sop/foreground_package.dart';
import 'package:test/test.dart';

void main() {
  test('parses package from mResumedActivity line', () {
    const out = '''
  ResumedActivity: ActivityRecord{a1b2 u0 com.tencent.mm/.ui.LauncherUI t42}
  mResumedActivity: ActivityRecord{a1b2 u0 com.tencent.mm/.ui.LauncherUI t42}
''';
    expect(parseForegroundPackage(out), 'com.tencent.mm');
  });

  test('returns null when no resumed activity present', () {
    expect(parseForegroundPackage('nothing here'), isNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/agent/sop/foreground_package_test.dart`
Expected: FAIL — `parseForegroundPackage` undefined.

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/src/agent/sop/foreground_package.dart
import 'package:logger_utils/logger_utils.dart';
import 'package:scrcpy_client/scrcpy_client.dart';

final _log = Logger('scrcpy.mcp.sop.foreground');

/// Extracts the foreground app package from `dumpsys activity activities`
/// output by matching a `ResumedActivity: ActivityRecord{... u0 <pkg>/<act>}`
/// line. Returns null when no resumed activity is found.
String? parseForegroundPackage(String dumpsysOutput) {
  final re = RegExp(r'ResumedActivity.*?\bu\d+\s+([\w.]+)/');
  final m = re.firstMatch(dumpsysOutput);
  return m?.group(1);
}

/// Best-effort foreground package via adb. Returns null on any failure.
Future<String?> foregroundPackage(ScrcpyAdb adb, String deviceId) async {
  try {
    final r = await adb.shell(
      ['dumpsys', 'activity', 'activities'],
      deviceId: deviceId,
    );
    return parseForegroundPackage(r.stdout as String);
  } catch (e) {
    _log.warning('foreground package lookup failed: $e');
    return null;
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `dart test test/agent/sop/foreground_package_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/src/agent/sop/foreground_package.dart test/agent/sop/foreground_package_test.dart
git commit -m "feat(scrcpy_mcp): add foreground package detection"
```

---

### Task 4: PhoneAgent 轨迹收集 + guidance 注入

**Files:**
- Modify: `lib/src/agent/agent_config.dart`
- Modify: `lib/src/agent/phone_agent.dart`
- Test: `test/phone_agent_test.dart` (扩充)

**Interfaces:**
- Produces: `AgentResult` 新增 `final List<String> trajectory;`（默认 `const []`）+ `AgentResult copyWith({List<String>? trajectory})`；`PhoneAgent.run(String message, {String? guidance})`。
- Consumes: `actionSummary` from `action_summary.dart`（已存在）。

- [ ] **Step 1: Write the failing test**

```dart
// 追加到 test/phone_agent_test.dart 的 main() 内（复用文件已有 import 与 fake）
test('returns action trajectory and injects guidance', () async {
  final seen = <String>[];
  var i = 0;
  final client = FakeModelClient(({required messages}) async {
    // capture the step-0 user text to assert guidance injection
    for (final m in messages) {
      if (m.role == 'user' && m.textContent != null) seen.add(m.textContent!);
    }
    return i++ == 0
        ? const LlmResponse(text: 'do(action="Tap", element=[1,2])')
        : const LlmResponse(text: 'finish(message="done")');
  });
  final agent = PhoneAgent(
    config: const AgentConfig(maxSteps: 5),
    client: client,
    takeScreenshot: () async => (base64: 'AAA$i', mimeType: 'image/png'),
    actionRunner: (a) async => 'ok',
  );
  final result = await agent.run('开门', guidance: '参考：先点首页');
  expect(result.success, isTrue);
  expect(result.trajectory, isNotEmpty);
  expect(result.trajectory.first, contains('Tap'));
  expect(seen.any((t) => t.contains('参考：先点首页')), isTrue);
});
```

> 注：若 `phone_agent_test.dart` 未 import `FakeModelClient`/`LlmResponse`/`AgentConfig`，补上 `import 'utils/fake_model_client.dart';` 与相应 `package:scrcpy_mcp/...` import。

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/phone_agent_test.dart -N 'returns action trajectory'`
Expected: FAIL — `run` has no named param `guidance` / `trajectory` undefined.

- [ ] **Step 3a: Extend AgentResult in `agent_config.dart`**

```dart
class AgentResult {
  const AgentResult({
    required this.result,
    required this.steps,
    required this.success,
    this.trajectory = const [],
  });

  final String result;
  final int steps;
  final bool success;

  /// One-line summaries of the actions taken, oldest first. Used by SopWriter.
  final List<String> trajectory;

  AgentResult copyWith({List<String>? trajectory}) => AgentResult(
    result: result,
    steps: steps,
    success: success,
    trajectory: trajectory ?? this.trajectory,
  );
}
```

- [ ] **Step 3b: Collect trajectory + inject guidance in `phone_agent.dart`**

In `run`, change the signature and add a trajectory list + a single wrapping helper:

```dart
Future<AgentResult> run(String message, {String? guidance}) async {
  _log.info('task: $message');
  final messages = _buildInitialMessages();
  final memories = <String>[];
  final trajectory = <String>[];
  AgentResult done(AgentResult r) => r.copyWith(trajectory: List.of(trajectory));
  // ... existing locals unchanged ...
```

Pass `guidance` into `_buildUserContent`:

```dart
final userContent = _buildUserContent(
  step,
  message,
  lastResult,
  memories,
  guidance,
);
```

Append a summary for each parsed action (in the `ParsedAction` case, right after `_log.info('step $step  ${actionSummary(action)}');`):

```dart
trajectory.add(actionSummary(action));
```

Wrap every `return` of an `AgentResult` inside `run` with `done(...)`:
- `return done(stall);`
- the parse-failure `return done(AgentResult(...));`
- `if (outcome.done != null) return done(outcome.done!);`
- final `return done(exhausted);`

Update `_buildUserContent` to accept and inject guidance at step 0:

```dart
String _buildUserContent(
  int step,
  String message,
  String? lastResult,
  List<String> memories,
  String? guidance,
) {
  if (step == 0) {
    return guidance == null || guidance.isEmpty
        ? message
        : '参考经验：\n$guidance\n\n任务：$message';
  }
  // ... rest unchanged ...
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `dart test test/phone_agent_test.dart`
Expected: PASS (existing tests + the new one).

- [ ] **Step 5: Commit**

```bash
git add lib/src/agent/agent_config.dart lib/src/agent/phone_agent.dart test/phone_agent_test.dart
git commit -m "feat(scrcpy_mcp): PhoneAgent trajectory output and guidance injection"
```

---

### Task 5: SopRetriever

**Files:**
- Create: `lib/src/agent/sop/sop_retriever.dart`
- Test: `test/agent/sop/sop_retriever_test.dart`

**Interfaces:**
- Consumes: `AgentModelClient` (`chat`), `SopRecord`.
- Produces: `class SopRetriever { SopRetriever(AgentModelClient client); Future<List<SopRecord>> select({required String taskText, required List<SopRecord> candidates, int limit = 3}); }`。空候选直接返回 `[]`；让 LLM 返回逗号分隔的下标，解析后按 limit 截断。

- [ ] **Step 1: Write the failing test**

```dart
// test/agent/sop/sop_retriever_test.dart
import 'package:scrcpy_mcp/src/agent/sop/sop_record.dart';
import 'package:scrcpy_mcp/src/agent/sop/sop_retriever.dart';
import 'package:test/test.dart';
import '../../utils/fake_model_client.dart';

SopRecord rec(String id, String intent) => SopRecord(
  id: id,
  package: 'com.app',
  intent: intent,
  polarity: SopPolarity.positive,
  steps: const ['a'],
  sourceTask: 't',
  createdAt: DateTime.utc(2026, 6, 18),
);

void main() {
  test('returns [] without calling LLM when no candidates', () async {
    var called = false;
    final r = SopRetriever(FakeModelClient(({required messages}) async {
      called = true;
      return const LlmResponse(text: '0');
    }));
    expect(await r.select(taskText: 'x', candidates: const []), isEmpty);
    expect(called, isFalse);
  });

  test('selects records by LLM-returned indices, capped at limit', () async {
    final r = SopRetriever(FakeModelClient(
      ({required messages}) async => const LlmResponse(text: '相关：2, 0'),
    ));
    final picked = await r.select(
      taskText: '转账',
      candidates: [rec('a', '充值'), rec('b', '设置'), rec('c', '转账')],
      limit: 3,
    );
    expect(picked.map((p) => p.id), ['c', 'a']);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/agent/sop/sop_retriever_test.dart`
Expected: FAIL — `SopRetriever` undefined.

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/src/agent/sop/sop_retriever.dart
import 'package:logger_utils/logger_utils.dart';

import '../agent_model_client.dart';
import '../llm_client.dart';
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `dart test test/agent/sop/sop_retriever_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/src/agent/sop/sop_retriever.dart test/agent/sop/sop_retriever_test.dart
git commit -m "feat(scrcpy_mcp): add SopRetriever LLM-based SOP selection"
```

---

### Task 6: SopWriter

**Files:**
- Create: `lib/src/agent/sop/sop_writer.dart`
- Test: `test/agent/sop/sop_writer_test.dart`

**Interfaces:**
- Consumes: `AgentModelClient`, `SopStore`, `SopRecord`, `SopPolarity`.
- Produces: `class SopWriter { SopWriter(AgentModelClient client, SopStore store); Future<void> write({required String package, required String taskText, required bool success, required List<String> trajectory, String? deviceHint}); }`。让 LLM 返回 `{"intent","steps":[...],"pitfall"}` JSON，构造 record（polarity 由 success 决定，id 用时间戳）并 `append`。

- [ ] **Step 1: Write the failing test**

```dart
// test/agent/sop/sop_writer_test.dart
import 'dart:io';
import 'package:scrcpy_mcp/src/agent/sop/sop_record.dart';
import 'package:scrcpy_mcp/src/agent/sop/sop_store.dart';
import 'package:scrcpy_mcp/src/agent/sop/sop_writer.dart';
import 'package:test/test.dart';
import '../../utils/fake_model_client.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('sop_w'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('writes a positive SOP from a successful run', () async {
    final store = SopStore(dir.path);
    final writer = SopWriter(
      FakeModelClient(({required messages}) async => const LlmResponse(
        text: '{"intent":"转账","steps":["进聊天","点+"],"pitfall":null}',
      )),
      store,
    );
    await writer.write(
      package: 'com.app',
      taskText: '给张三转账',
      success: true,
      trajectory: const ['Tap(1,2)', 'Finish("done")'],
    );
    final loaded = await store.load('com.app');
    expect(loaded, hasLength(1));
    expect(loaded.first.polarity, SopPolarity.positive);
    expect(loaded.first.intent, '转账');
    expect(loaded.first.steps, ['进聊天', '点+']);
  });

  test('writes a negative SOP with pitfall from a failed run', () async {
    final store = SopStore(dir.path);
    final writer = SopWriter(
      FakeModelClient(({required messages}) async => const LlmResponse(
        text: '{"intent":"转账","steps":["进聊天"],"pitfall":"被引导蒙层挡住"}',
      )),
      store,
    );
    await writer.write(
      package: 'com.app',
      taskText: '给张三转账',
      success: false,
      trajectory: const ['Tap(1,2)'],
    );
    final loaded = await store.load('com.app');
    expect(loaded.first.polarity, SopPolarity.negative);
    expect(loaded.first.pitfall, '被引导蒙层挡住');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/agent/sop/sop_writer_test.dart`
Expected: FAIL — `SopWriter` undefined.

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/src/agent/sop/sop_writer.dart
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
    final prompt =
        '任务：$taskText\n执行结果：$outcome\n动作轨迹：\n${trajectory.join('\n')}\n\n'
        '请总结成 JSON：{"intent":"意图标题","steps":["意图级步骤"],'
        '"pitfall":"${success ? 'null（成功可为 null）' : '失败的关键坑点'}"}。'
        '只输出 JSON。';
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
    _log.info('wrote ${record.polarity.name} SOP for $package: ${record.intent}');
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `dart test test/agent/sop/sop_writer_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/src/agent/sop/sop_writer.dart test/agent/sop/sop_writer_test.dart
git commit -m "feat(scrcpy_mcp): add SopWriter trajectory summarization"
```

---

### Task 7: 接入 RunTaskTool（编排 + best-effort）

**Files:**
- Modify: `lib/src/agent/agent_config.dart` (`AgentConfig` 增 `sopDir`)
- Modify: `lib/src/tools/run_task.dart`
- Test: `test/run_task_tool_test.dart` (扩充)

**Interfaces:**
- Consumes: `SopStore`, `SopRetriever`, `SopWriter`, `foregroundPackage`, `SopRecord`, `SopPolarity`，`AgentResult.trajectory`，`PhoneAgent.run(message, guidance:)`。
- Produces: SOP 文件写入 `<sopDir>/sop/<package>.jsonl`；`AgentConfig.sopDir`（null=禁用）。

- [ ] **Step 1: Write the failing test**

```dart
// 追加到 test/run_task_tool_test.dart：用临时 sopDir 起一个 server，跑成功任务后断言落库。
// 需要在 setUp 处用带 sopDir 的 AgentConfig，并让 MockAdb.shell 返回一个前台包名。
//
// 新增一个独立 group，自带 server 构造（不复用顶部 setUp），示例：
test('writes a SOP after a successful run', () async {
  final dir = Directory.systemTemp.createTempSync('sop_rt');
  addTearDown(() => dir.deleteSync(recursive: true));

  final server = ScrcpyMcpServer(
    session: MockScrcpySession(),
    adb: _ResumedActivityAdb(), // shell 返回含 mResumedActivity 的输出
    agentConfig: AgentConfig(maxSteps: 5, sopDir: dir.path),
    client: FakeModelClient(({required messages}) async {
      // 第一次（agent 决策）finish；之后（writer 总结）返回 JSON。
      final isSummary = messages.any(
        (m) => (m.textContent ?? '').contains('请总结成 JSON'),
      );
      return isSummary
          ? const LlmResponse(
              text: '{"intent":"打开应用","steps":["点图标"],"pitfall":null}')
          : const LlmResponse(text: 'finish(message="done")');
    }),
  );
  // ... 通过 McpClient 调用 run_task(device_id, message) ...
  // 断言：
  final f = File('${dir.path}/sop/com.demo.app.jsonl');
  expect(f.existsSync(), isTrue);
  expect(f.readAsStringSync(), contains('"intent":"打开应用"'));
});
```

> `_ResumedActivityAdb` 是一个 `extends MockAdb` 的小 fake，覆写 `shell` 在收到 `dumpsys activity activities` 时返回
> `'mResumedActivity: ActivityRecord{x u0 com.demo.app/.Main t1}'`，其余调用沿用父类。`ScrcpyMcpServer` 构造参数名以现有源码为准（参考 `lib/src/scrcpy_mcp_server.dart` 与现有测试 setUp）。

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/run_task_tool_test.dart -N 'writes a SOP'`
Expected: FAIL — `sopDir` 不是 `AgentConfig` 的命名参数 / 未落库。

- [ ] **Step 3a: Add `sopDir` to `AgentConfig`**

```dart
const AgentConfig({
  this.maxSteps = 15,
  this.keepScreenshots = 3,
  this.stallThreshold = 3,
  this.repeatedActionThreshold = 10,
  this.screenSize,
  this.sopDir,
});

/// Base dir for the SOP memory store. Null disables the SOP feature entirely.
final String? sopDir;
```

- [ ] **Step 3b: Orchestrate in `run_task.dart`**

Add imports:

```dart
import '../agent/sop/foreground_package.dart';
import '../agent/sop/sop_record.dart';
import '../agent/sop/sop_retriever.dart';
import '../agent/sop/sop_store.dart';
import '../agent/sop/sop_writer.dart';
```

Before `agent.run`, retrieve (best-effort):

```dart
final sopDir = _config.sopDir;
SopStore? store;
String? package;
String? guidance;
if (sopDir != null) {
  try {
    store = SopStore(sopDir);
    package = await foregroundPackage(_adb, deviceId);
    if (package != null) {
      final picked = await SopRetriever(_client).select(
        taskText: message,
        candidates: await store.load(package),
      );
      if (picked.isNotEmpty) guidance = _formatGuidance(picked);
    }
  } catch (e) {
    logger.warning('sop retrieve failed: $e');
  }
}

final result = await agent.run(message, guidance: guidance);
```

After computing `result`, write back (best-effort) before returning the
`CallToolResult`:

```dart
if (store != null && package != null) {
  try {
    await SopWriter(_client, store).write(
      package: package,
      taskText: message,
      success: result.success,
      trajectory: result.trajectory,
    );
  } catch (e) {
    logger.warning('sop writeback failed: $e');
  }
}
```

Add the guidance formatter as a top-level/private helper in the file:

```dart
String _formatGuidance(List<SopRecord> sops) {
  final pos = sops.where((s) => s.polarity == SopPolarity.positive);
  final neg = sops.where((s) => s.polarity == SopPolarity.negative);
  final b = StringBuffer();
  if (pos.isNotEmpty) {
    b.writeln('可参考以下成功流程：');
    for (final s in pos) b.writeln('- ${s.intent}：${s.steps.join(' → ')}');
  }
  if (neg.isNotEmpty) {
    b.writeln('注意避免以下坑：');
    for (final s in neg) {
      b.writeln('- ${s.intent}：${s.pitfall ?? s.steps.join(' → ')}');
    }
  }
  return b.toString().trim();
}
```

- [ ] **Step 4: Run the full suite to verify it passes**

Run: `dart test -x real-device`
Expected: PASS — new SOP test passes; all existing tests still green.

- [ ] **Step 5: Commit**

```bash
git add lib/src/agent/agent_config.dart lib/src/tools/run_task.dart test/run_task_tool_test.dart
git commit -m "feat(scrcpy_mcp): wire SOP memory into run_task (retrieve/inject/writeback)"
```

---

### Task 8: 接线 sopDir 到 server 入口 + analyze/format

**Files:**
- Modify: `lib/src/scrcpy_mcp_server.dart`（若 `AgentConfig` 由调用方传入则无需改；本任务确认 sopDir 能从配置流到 `RunTaskTool`）
- 验证全仓 analyze/format。

**Interfaces:**
- Consumes: `AgentConfig.sopDir`。

- [ ] **Step 1: 确认 sopDir 透传**

检查 `lib/src/scrcpy_mcp_server.dart` 如何拿到 `AgentConfig` 并传给 `RunTaskTool`（见 server 第 ~108 行）。`RunTaskTool` 已持有 `_config`，故只要构造 `ScrcpyMcpServer` 时传入带 `sopDir` 的 `AgentConfig` 即可，无需改 server 内部。若入口（main / bin）硬编码了 `AgentConfig`，在那里补上 `sopDir`（来源：环境变量或配置文件，按现有配置读取方式）。

- [ ] **Step 2: Analyze + format**

Run（在仓库根）:
```bash
melos run analyze
melos run format
```
Expected: 无 error/warning/info；format 无 diff。

- [ ] **Step 3: 全量测试**

Run: `cd scrcpy_mcp && dart test -x real-device`
Expected: 全绿。

- [ ] **Step 4: Commit（若有改动）**

```bash
git add -A
git commit -m "chore(scrcpy_mcp): wire sopDir through server entry; analyze/format"
```

---

## Self-Review

- **Spec coverage:** 数据模型→T1；存储 jsonl→T2；前台包名→T3；轨迹+注入→T4；检索→T5；回写正/反例→T6；run_task 编排+best-effort+sopDir 禁用开关→T7；接线/analyze→T8。测试策略（temp dir、mock LLM/adb、-x real-device）贯穿各任务。✅
- **Placeholder scan:** 各代码步骤均给出完整实现；T7/T8 中"按现有配置读取方式""构造参数名以现有源码为准"为对既有代码的对齐说明，非待填实现。✅
- **Type consistency:** `SopRecord`/`SopPolarity` 字段、`SopStore.load/append`、`SopRetriever.select`、`SopWriter.write`、`AgentResult.trajectory/copyWith`、`PhoneAgent.run(message,{guidance})`、`parseForegroundPackage/foregroundPackage` 在各任务签名一致。✅
