import 'package:flutter/services.dart';

/// Maps a Flutter [PhysicalKeyboardKey] to the corresponding Android
/// `AKEYCODE_*` integer.
///
/// Uses physical key positions so behaviour is consistent across keyboard
/// layouts (a French AZERTY user pressing the physical Q-position key
/// produces `KEYCODE_Q`, not `KEYCODE_A`).
///
/// Returns `null` for keys that have no Android equivalent.
int? androidKeycodeForPhysicalKey(PhysicalKeyboardKey key) => _map[key];

final Map<PhysicalKeyboardKey, int> _map = {
  // ── Letters A-Z (29-54) ───────────────────────────────────────────────
  PhysicalKeyboardKey.keyA: 29,
  PhysicalKeyboardKey.keyB: 30,
  PhysicalKeyboardKey.keyC: 31,
  PhysicalKeyboardKey.keyD: 32,
  PhysicalKeyboardKey.keyE: 33,
  PhysicalKeyboardKey.keyF: 34,
  PhysicalKeyboardKey.keyG: 35,
  PhysicalKeyboardKey.keyH: 36,
  PhysicalKeyboardKey.keyI: 37,
  PhysicalKeyboardKey.keyJ: 38,
  PhysicalKeyboardKey.keyK: 39,
  PhysicalKeyboardKey.keyL: 40,
  PhysicalKeyboardKey.keyM: 41,
  PhysicalKeyboardKey.keyN: 42,
  PhysicalKeyboardKey.keyO: 43,
  PhysicalKeyboardKey.keyP: 44,
  PhysicalKeyboardKey.keyQ: 45,
  PhysicalKeyboardKey.keyR: 46,
  PhysicalKeyboardKey.keyS: 47,
  PhysicalKeyboardKey.keyT: 48,
  PhysicalKeyboardKey.keyU: 49,
  PhysicalKeyboardKey.keyV: 50,
  PhysicalKeyboardKey.keyW: 51,
  PhysicalKeyboardKey.keyX: 52,
  PhysicalKeyboardKey.keyY: 53,
  PhysicalKeyboardKey.keyZ: 54,

  // ── Digits 0-9 (7-16) ────────────────────────────────────────────────
  PhysicalKeyboardKey.digit0: 7,
  PhysicalKeyboardKey.digit1: 8,
  PhysicalKeyboardKey.digit2: 9,
  PhysicalKeyboardKey.digit3: 10,
  PhysicalKeyboardKey.digit4: 11,
  PhysicalKeyboardKey.digit5: 12,
  PhysicalKeyboardKey.digit6: 13,
  PhysicalKeyboardKey.digit7: 14,
  PhysicalKeyboardKey.digit8: 15,
  PhysicalKeyboardKey.digit9: 16,

  // ── Whitespace & navigation ──────────────────────────────────────────
  PhysicalKeyboardKey.enter: 66, // KEYCODE_ENTER
  PhysicalKeyboardKey.backspace: 67, // KEYCODE_DEL
  PhysicalKeyboardKey.delete: 112, // KEYCODE_FORWARD_DEL
  PhysicalKeyboardKey.escape: 111, // KEYCODE_ESCAPE
  PhysicalKeyboardKey.tab: 61, // KEYCODE_TAB
  PhysicalKeyboardKey.space: 62, // KEYCODE_SPACE
  // ── Arrow keys ────────────────────────────────────────────────────────
  PhysicalKeyboardKey.arrowUp: 19,
  PhysicalKeyboardKey.arrowDown: 20,
  PhysicalKeyboardKey.arrowLeft: 21,
  PhysicalKeyboardKey.arrowRight: 22,

  // ── Function keys F1-F12 (131-142) ───────────────────────────────────
  PhysicalKeyboardKey.f1: 131,
  PhysicalKeyboardKey.f2: 132,
  PhysicalKeyboardKey.f3: 133,
  PhysicalKeyboardKey.f4: 134,
  PhysicalKeyboardKey.f5: 135,
  PhysicalKeyboardKey.f6: 136,
  PhysicalKeyboardKey.f7: 137,
  PhysicalKeyboardKey.f8: 138,
  PhysicalKeyboardKey.f9: 139,
  PhysicalKeyboardKey.f10: 140,
  PhysicalKeyboardKey.f11: 141,
  PhysicalKeyboardKey.f12: 142,

  // ── Navigation / editing ──────────────────────────────────────────────
  PhysicalKeyboardKey.home: 3, // KEYCODE_HOME
  PhysicalKeyboardKey.end: 123, // KEYCODE_MOVE_END
  PhysicalKeyboardKey.pageUp: 92, // KEYCODE_PAGE_UP
  PhysicalKeyboardKey.pageDown: 93, // KEYCODE_PAGE_DOWN
  PhysicalKeyboardKey.insert: 124, // KEYCODE_INSERT
  // ── Lock keys ─────────────────────────────────────────────────────────
  PhysicalKeyboardKey.capsLock: 115, // KEYCODE_CAPS_LOCK
  PhysicalKeyboardKey.scrollLock: 116,

  // ── Punctuation / symbols ─────────────────────────────────────────────
  PhysicalKeyboardKey.minus: 69, // KEYCODE_MINUS
  PhysicalKeyboardKey.equal: 70, // KEYCODE_EQUALS
  PhysicalKeyboardKey.bracketLeft: 71, // KEYCODE_LEFT_BRACKET
  PhysicalKeyboardKey.bracketRight: 72,
  PhysicalKeyboardKey.backslash: 73,
  PhysicalKeyboardKey.semicolon: 74,
  PhysicalKeyboardKey.quote: 75,
  PhysicalKeyboardKey.comma: 55,
  PhysicalKeyboardKey.period: 56,
  PhysicalKeyboardKey.slash: 76,
  PhysicalKeyboardKey.backquote: 68,

  // ── Modifier keys ────────────────────────────────────────────────────
  PhysicalKeyboardKey.shiftLeft: 59, // KEYCODE_SHIFT_LEFT
  PhysicalKeyboardKey.shiftRight: 60, // KEYCODE_SHIFT_RIGHT
  PhysicalKeyboardKey.altLeft: 57, // KEYCODE_ALT_LEFT
  PhysicalKeyboardKey.altRight: 58, // KEYCODE_ALT_RIGHT
  PhysicalKeyboardKey.controlLeft: 113, // KEYCODE_CTRL_LEFT
  PhysicalKeyboardKey.controlRight: 114,
  PhysicalKeyboardKey.metaLeft: 117, // KEYCODE_META_LEFT
  PhysicalKeyboardKey.metaRight: 118,
};
