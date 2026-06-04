---
name: verify-on-device
description: Run scrcpy_mcp real-device e2e/agent tests against a connected Android phone. Resets the device to home, runs the real-device test(s), and reports the autoglm-phone agent's action sequence and final result. Use to verify coordinate/tap fixes, Type behavior, or any change needing on-device confirmation.
disable-model-invocation: true
---

# verify-on-device

User-invoked workflow to verify scrcpy_mcp behavior on a **real connected Android device**. Has side effects (drives the phone), so it is user-only.

## Arguments

- `$1` (optional): test file, relative to `scrcpy_mcp/`. Default: `test/phone_agent_test/phone_agent_test_real.dart` (the open-Twitter agent e2e).
- `$2` (optional): device serial. Default: first connected device from `adb devices`.

## Steps

1. Confirm a device is connected: `adb devices`. If none, tell the user and stop.
2. Run the bundled script (it resets to home, runs the test, and extracts the agent actions + result):

   ```bash
   "$CLAUDE_PROJECT_DIR"/.claude/skills/verify-on-device/scripts/run-e2e.sh "$1" "$2"
   ```

3. Read the printed **model actions** and **result**. Then assess:
   - Did taps land / did the agent progress through changing screens (not loop on one spot)?
   - If a `finish(...)` or visual check failed, is it a real control bug or a flaky assertion / transient overlay (e.g. an X "Premium" upsell)?
   - For a deeper look, capture the final screen with `adb -s <serial> exec-out screencap -p > /tmp/final.png` and Read it.
4. Report a short verdict: what worked, what failed, and whether the failure is a code bug or environmental.

## Notes

- autoglm-phone emits `[0,1000]` normalized coordinates — see `scrcpy_mcp/lib/src/tools/run_task.dart` (`_kCoordSpace`). The adb-driven e2e converts them to device pixels via `wm size`.
- Real-device tests are tagged `real-device` and excluded from `melos run test`; this skill runs them explicitly with `--tags real-device`.
- The full test log path is printed at the end for grepping (screenshots are base64 in the log; filter them out).
