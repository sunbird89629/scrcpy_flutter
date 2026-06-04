# Visual Assertion Helper Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Provide a reusable VLM-based visual assertion helper for scrcpy_mcp tests, with a deterministic offline-testable parser at its core.

**Architecture:** A shared test helper `test/phone_agent_test/visual_assertion.dart` with three layers — a pure `parseScreenCheckResponse` parser (unit-testable, no device/model), a `checkScreenContains` core that asks the vision model, and a `checkDeviceScreenContains` convenience wrapper that captures the screenshot first. Existing tests are refactored onto it.

**Tech Stack:** Dart, `package:test`, `package:scrcpy_mcp` (exports `LlmClient`, `LlmMessage`, `LlmResponse`, `LlmException`, `ScrcpyMcpAdb`, `AutoglmLlmClient`).

**Spec:** `docs/superpowers/specs/2026-06-02-visual-assertion-helper-design.md`

---

## File Structure

- **Create** `test/phone_agent_test/visual_assertion.dart` — the helper: `ScreenCheckResult`, `parseScreenCheckResponse`, `checkScreenContains`, `checkDeviceScreenContains`.
- **Create** `test/phone_agent_test/visual_assertion_test.dart` — deterministic unit tests (parser + core with a fake `LlmClient`). No device/model required.
- **Modify** `test/phone_agent_test/screenshot_content_test.dart` — refactor onto the helper; remove private `_askModel`; fix the `contains('是')` misjudgment.
- **Modify** `test/phone_agent_test/phone_agent_test_real.dart` — add a real success check after `agent.run()`.

All commands run from `scrcpy_mcp/` (a pure Dart package). Single-file test runs use `dart test <path>`.

---

### Task 1: Parser + result type

**Files:**
- Create: `test/phone_agent_test/visual_assertion.dart`
- Test: `test/phone_agent_test/visual_assertion_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/phone_agent_test/visual_assertion_test.dart`:

```dart
import 'package:scrcpy_mcp/scrcpy_mcp.dart';
import 'package:test/test.dart';

import 'visual_assertion.dart';

void main() {
  group('parseScreenCheckResponse', () {
    test('leading 是 → matched', () {
      final r = parseScreenCheckResponse('是\n界面上有应用图标');
      expect(r.matched, isTrue);
      expect(r.reason, contains('应用图标'));
    });

    test('bare 是 → matched', () {
      expect(parseScreenCheckResponse('是').matched, isTrue);
    });

    test('leading 否 → not matched', () {
      expect(parseScreenCheckResponse('否\n没有看到').matched, isFalse);
    });

    test('不是 → not matched (regression for contains("是") bug)', () {
      expect(parseScreenCheckResponse('不是').matched, isFalse);
    });

    test('leading/trailing whitespace tolerated', () {
      expect(parseScreenCheckResponse('  是  ').matched, isTrue);
    });

    test('only first line decides', () {
      expect(parseScreenCheckResponse('否\n是的部分内容相似').matched, isFalse);
    });

    test('empty → throws LlmException', () {
      expect(() => parseScreenCheckResponse(''), throwsA(isA<LlmException>()));
    });

    test('whitespace-only → throws LlmException', () {
      expect(() => parseScreenCheckResponse('   \n  '),
          throwsA(isA<LlmException>()));
    });

    test('unparseable prose → throws LlmException', () {
      expect(() => parseScreenCheckResponse('这个界面看起来像桌面'),
          throwsA(isA<LlmException>()));
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/phone_agent_test/visual_assertion_test.dart`
Expected: FAIL — `visual_assertion.dart` does not exist / `parseScreenCheckResponse` undefined.

- [ ] **Step 3: Write minimal implementation**

Create `test/phone_agent_test/visual_assertion.dart`:

```dart
import 'package:scrcpy_mcp/scrcpy_mcp.dart';

/// Result of a visual assertion against a screenshot.
class ScreenCheckResult {
  const ScreenCheckResult({required this.matched, required this.reason});

  /// Whether the model judged the expectation present on screen.
  final bool matched;

  /// The model's full reply, surfaced via `expect(..., reason: r.reason)`.
  final String reason;
}

/// Parses a raw vision-model reply into a [ScreenCheckResult].
///
/// Rules: trim, take the first line. Leading "否"/"不" → not matched;
/// leading "是" → matched; anything else (including empty) → [LlmException].
/// Checking "否"/"不" before "是" avoids the `contains('是')` misjudgment
/// where "不是" was wrongly read as a match.
ScreenCheckResult parseScreenCheckResponse(String raw) {
  final text = raw.trim();
  if (text.isEmpty) {
    throw const LlmException('Empty response from vision model');
  }
  final firstLine = text.split('\n').first.trim();
  if (firstLine.startsWith('否') || firstLine.startsWith('不')) {
    return ScreenCheckResult(matched: false, reason: text);
  }
  if (firstLine.startsWith('是')) {
    return ScreenCheckResult(matched: true, reason: text);
  }
  throw LlmException('Unparseable vision response: $raw');
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `dart test test/phone_agent_test/visual_assertion_test.dart`
Expected: PASS (9 tests).

- [ ] **Step 5: Commit**

```bash
git add test/phone_agent_test/visual_assertion.dart test/phone_agent_test/visual_assertion_test.dart
git commit -m "test(scrcpy_mcp): add visual assertion parser

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: `checkScreenContains` core

**Files:**
- Modify: `test/phone_agent_test/visual_assertion.dart`
- Test: `test/phone_agent_test/visual_assertion_test.dart`

- [ ] **Step 1: Write the failing test**

Add to `test/phone_agent_test/visual_assertion_test.dart` — a fake client at the bottom of the file, and a new group inside `main()` after the existing group:

```dart
// Inside main(), after the parseScreenCheckResponse group:
  group('checkScreenContains', () {
    test('wires messages and parses 是', () async {
      final fake = _FakeLlmClient('是\n有图标');
      final r = await checkScreenContains(
        client: fake,
        base64Screenshot: 'AAAA',
        expectation: '应用图标',
      );
      expect(r.matched, isTrue);

      final msgs = fake.captured!;
      expect(msgs.first.role, 'system');
      expect(msgs.first.textContent, contains('是'));
      final user = msgs.last;
      expect(user.role, 'user');
      expect(user.textContent, contains('应用图标'));
      expect(user.imageBase64, 'AAAA');
      expect(user.imageMimeType, 'image/png');
    });

    test('parses 否 as not matched', () async {
      final r = await checkScreenContains(
        client: _FakeLlmClient('否'),
        base64Screenshot: 'AAAA',
        expectation: '计算器',
      );
      expect(r.matched, isFalse);
    });

    test('empty model reply throws LlmException', () {
      expect(
        () => checkScreenContains(
          client: _FakeLlmClient(''),
          base64Screenshot: 'AAAA',
          expectation: 'x',
        ),
        throwsA(isA<LlmException>()),
      );
    });
  });

// At the very bottom of the file, outside main():
class _FakeLlmClient implements LlmClient {
  _FakeLlmClient(this.reply);

  final String reply;
  List<LlmMessage>? captured;

  @override
  Future<LlmResponse> chat({required List<LlmMessage> messages}) async {
    captured = messages;
    return LlmResponse(text: reply);
  }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/phone_agent_test/visual_assertion_test.dart`
Expected: FAIL — `checkScreenContains` undefined.

- [ ] **Step 3: Write minimal implementation**

Append to `test/phone_agent_test/visual_assertion.dart`:

```dart
const _systemPrompt =
    '你是一个手机界面分析助手。请根据截图判断用户描述的内容或状态是否出现在界面上。'
    '严格按以下格式回答：第一行只写"是"或"否"，第二行起简要说明理由。';

/// Asks [client] whether [expectation] appears in [base64Screenshot].
/// Throws [LlmException] if the reply can't be parsed.
Future<ScreenCheckResult> checkScreenContains({
  required LlmClient client,
  required String base64Screenshot,
  required String expectation,
  String mimeType = 'image/png',
}) async {
  final response = await client.chat(
    messages: [
      const LlmMessage(role: 'system', textContent: _systemPrompt),
      LlmMessage(
        role: 'user',
        textContent: '界面上是否出现了"$expectation"？',
        imageBase64: base64Screenshot,
        imageMimeType: mimeType,
      ),
    ],
  );
  return parseScreenCheckResponse(response.text ?? '');
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `dart test test/phone_agent_test/visual_assertion_test.dart`
Expected: PASS (12 tests).

- [ ] **Step 5: Commit**

```bash
git add test/phone_agent_test/visual_assertion.dart test/phone_agent_test/visual_assertion_test.dart
git commit -m "feat(scrcpy_mcp): add checkScreenContains visual assertion core

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: `checkDeviceScreenContains` convenience wrapper

**Files:**
- Modify: `test/phone_agent_test/visual_assertion.dart`

This wrapper is a thin screenshot-then-check layer that depends on a real
`ScrcpyMcpAdb`; it is exercised by the refactored integration tests in Tasks 4–5
rather than a unit test (capturing real screenshot bytes adds no parser coverage
beyond Task 2).

- [ ] **Step 1: Add the wrapper**

Add the import at the top of `test/phone_agent_test/visual_assertion.dart`
(alongside the existing import):

```dart
import 'dart:convert';
```

Append at the end of the file:

```dart
/// Captures a screenshot from [deviceId] via [adb], then runs
/// [checkScreenContains].
Future<ScreenCheckResult> checkDeviceScreenContains({
  required LlmClient client,
  required ScrcpyMcpAdb adb,
  required String deviceId,
  required String expectation,
}) async {
  final bytes = await adb.takeScreenshot(deviceId);
  return checkScreenContains(
    client: client,
    base64Screenshot: base64Encode(bytes),
    expectation: expectation,
  );
}
```

- [ ] **Step 2: Verify it analyzes/compiles**

Run: `dart analyze test/phone_agent_test/visual_assertion.dart`
Expected: No issues found.

- [ ] **Step 3: Commit**

```bash
git add test/phone_agent_test/visual_assertion.dart
git commit -m "feat(scrcpy_mcp): add checkDeviceScreenContains wrapper

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: Refactor `screenshot_content_test.dart` onto the helper

**Files:**
- Modify: `test/phone_agent_test/screenshot_content_test.dart`

- [ ] **Step 1: Replace the file contents**

Rewrite `test/phone_agent_test/screenshot_content_test.dart` to use the helper,
dropping the private `_askModel` and the buggy `contains('是')` check:

```dart
import 'package:adb_tools/adb_tools.dart';
import 'package:logger_utils/logger_utils.dart';
import 'package:scrcpy_mcp/scrcpy_mcp.dart';
import 'package:test/test.dart';

import 'visual_assertion.dart';

const _deviceId = '39111FDJH00D47';

void main() {
  test(
    'screenshot contains app icons',
    () async {
      initLogging();
      final adb = ScrcpyMcpAdb(AdbClient());
      final client = AutoglmLlmClient.fromTest();

      final r = await checkDeviceScreenContains(
        client: client,
        adb: adb,
        deviceId: _deviceId,
        expectation: '应用图标',
      );

      expect(r.matched, isTrue, reason: r.reason);
    },
    timeout: const Timeout(Duration(minutes: 1)),
    skip: false,
  );

  test(
    'screenshot does not contain a calculator app',
    () async {
      initLogging();
      final adb = ScrcpyMcpAdb(AdbClient());
      final client = AutoglmLlmClient.fromTest();

      // Desktop should not contain a calculator app specifically.
      final r = await checkDeviceScreenContains(
        client: client,
        adb: adb,
        deviceId: _deviceId,
        expectation: '计算器',
      );

      expect(r.matched, isFalse, reason: r.reason);
    },
    timeout: const Timeout(Duration(minutes: 1)),
    skip: false,
  );
}
```

- [ ] **Step 2: Verify it analyzes**

Run: `dart analyze test/phone_agent_test/screenshot_content_test.dart`
Expected: No issues found. (No more unused `dart:convert` import, no `print`.)

- [ ] **Step 3: Commit**

```bash
git add test/phone_agent_test/screenshot_content_test.dart
git commit -m "refactor(scrcpy_mcp): use visual assertion helper in screenshot test

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 5: Add real success check to the e2e agent test

**Files:**
- Modify: `test/phone_agent_test/phone_agent_test_real.dart`

- [ ] **Step 1: Add the helper import**

In `test/phone_agent_test/phone_agent_test_real.dart`, add to the imports
(after the `package:test/test.dart` line):

```dart
import 'visual_assertion.dart';
```

- [ ] **Step 2: Replace the weak assertion with a real success check**

Find (around `phone_agent_test_real.dart:79-80`):

```dart
        final agentResult = await phoneAgent.run(_task);
        expect(agentResult, isNotNull);
```

Replace with:

```dart
        final agentResult = await phoneAgent.run(_task);
        expect(agentResult, isNotNull);

        // Verify the agent actually reached the Twitter homepage.
        final check = await checkDeviceScreenContains(
          client: AutoglmLlmClient.fromTest(),
          adb: adb,
          deviceId: _deviceId,
          expectation: 'Twitter（X）的主页',
        );
        expect(check.matched, isTrue, reason: check.reason);
```

- [ ] **Step 3: Verify it analyzes**

Run: `dart analyze test/phone_agent_test/phone_agent_test_real.dart`
Expected: No issues found.

- [ ] **Step 4: Run the deterministic unit suite (no device needed)**

Run: `dart test test/phone_agent_test/visual_assertion_test.dart`
Expected: PASS (12 tests) — confirms nothing regressed.

- [ ] **Step 5: Commit**

```bash
git add test/phone_agent_test/phone_agent_test_real.dart
git commit -m "test(scrcpy_mcp): verify e2e agent reaches target screen

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Notes for the implementer

- `scrcpy_mcp` is a pure Dart package; use `package:test` and `dart test` (not `flutter test`).
- Do not add `test` to dependencies — it is already a dev_dependency for this package.
- The integration tests (Tasks 4–5) require a physical Android device with id
  `39111FDJH00D47` and a working `AutoglmLlmClient.fromTest()`; they are expected
  to be run manually. The unit suite from Tasks 1–2 runs anywhere.
- `dart:convert`'s `base64Encode` is the only new import in the helper besides
  `package:scrcpy_mcp/scrcpy_mcp.dart`.
