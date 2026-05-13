import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_view/scrcpy_view.dart';

void main() {
  group('androidKeycodeForPhysicalKey', () {
    test('letter keys A-Z map to Android KEYCODE_A (29) through KEYCODE_Z (54)',
        () {
      expect(androidKeycodeForPhysicalKey(PhysicalKeyboardKey.keyA), 29);
      expect(androidKeycodeForPhysicalKey(PhysicalKeyboardKey.keyM), 41);
      expect(androidKeycodeForPhysicalKey(PhysicalKeyboardKey.keyZ), 54);
    });

    test('digit keys 0-9 map to KEYCODE_0 (7) through KEYCODE_9 (16)', () {
      expect(androidKeycodeForPhysicalKey(PhysicalKeyboardKey.digit0), 7);
      expect(androidKeycodeForPhysicalKey(PhysicalKeyboardKey.digit5), 12);
      expect(androidKeycodeForPhysicalKey(PhysicalKeyboardKey.digit9), 16);
    });

    test('common keys map correctly', () {
      expect(androidKeycodeForPhysicalKey(PhysicalKeyboardKey.enter), 66);
      expect(androidKeycodeForPhysicalKey(PhysicalKeyboardKey.backspace), 67);
      expect(androidKeycodeForPhysicalKey(PhysicalKeyboardKey.delete), 112);
      expect(androidKeycodeForPhysicalKey(PhysicalKeyboardKey.escape), 111);
      expect(androidKeycodeForPhysicalKey(PhysicalKeyboardKey.tab), 61);
      expect(androidKeycodeForPhysicalKey(PhysicalKeyboardKey.space), 62);
    });

    test('arrow keys map correctly', () {
      expect(androidKeycodeForPhysicalKey(PhysicalKeyboardKey.arrowUp), 19);
      expect(androidKeycodeForPhysicalKey(PhysicalKeyboardKey.arrowDown), 20);
      expect(androidKeycodeForPhysicalKey(PhysicalKeyboardKey.arrowLeft), 21);
      expect(androidKeycodeForPhysicalKey(PhysicalKeyboardKey.arrowRight), 22);
    });

    test('function keys F1-F12 map to 131-142', () {
      expect(androidKeycodeForPhysicalKey(PhysicalKeyboardKey.f1), 131);
      expect(androidKeycodeForPhysicalKey(PhysicalKeyboardKey.f6), 136);
      expect(androidKeycodeForPhysicalKey(PhysicalKeyboardKey.f12), 142);
    });

    test('modifier keys map to their Android keycodes', () {
      expect(androidKeycodeForPhysicalKey(PhysicalKeyboardKey.shiftLeft), 59);
      expect(androidKeycodeForPhysicalKey(PhysicalKeyboardKey.shiftRight), 60);
      expect(androidKeycodeForPhysicalKey(PhysicalKeyboardKey.altLeft), 57);
      expect(androidKeycodeForPhysicalKey(PhysicalKeyboardKey.altRight), 58);
      expect(
          androidKeycodeForPhysicalKey(PhysicalKeyboardKey.controlLeft), 113);
      expect(
          androidKeycodeForPhysicalKey(PhysicalKeyboardKey.controlRight), 114);
      expect(androidKeycodeForPhysicalKey(PhysicalKeyboardKey.metaLeft), 117);
      expect(androidKeycodeForPhysicalKey(PhysicalKeyboardKey.metaRight), 118);
    });

    test('navigation keys map correctly', () {
      expect(androidKeycodeForPhysicalKey(PhysicalKeyboardKey.home), 3);
      expect(androidKeycodeForPhysicalKey(PhysicalKeyboardKey.end), 123);
      expect(androidKeycodeForPhysicalKey(PhysicalKeyboardKey.pageUp), 92);
      expect(androidKeycodeForPhysicalKey(PhysicalKeyboardKey.pageDown), 93);
      expect(androidKeycodeForPhysicalKey(PhysicalKeyboardKey.insert), 124);
    });

    test('punctuation keys map correctly', () {
      expect(androidKeycodeForPhysicalKey(PhysicalKeyboardKey.minus), 69);
      expect(androidKeycodeForPhysicalKey(PhysicalKeyboardKey.equal), 70);
      expect(
          androidKeycodeForPhysicalKey(PhysicalKeyboardKey.bracketLeft), 71);
      expect(
          androidKeycodeForPhysicalKey(PhysicalKeyboardKey.bracketRight), 72);
      expect(androidKeycodeForPhysicalKey(PhysicalKeyboardKey.backslash), 73);
      expect(androidKeycodeForPhysicalKey(PhysicalKeyboardKey.semicolon), 74);
      expect(androidKeycodeForPhysicalKey(PhysicalKeyboardKey.quote), 75);
      expect(androidKeycodeForPhysicalKey(PhysicalKeyboardKey.comma), 55);
      expect(androidKeycodeForPhysicalKey(PhysicalKeyboardKey.period), 56);
      expect(androidKeycodeForPhysicalKey(PhysicalKeyboardKey.slash), 76);
      expect(androidKeycodeForPhysicalKey(PhysicalKeyboardKey.backquote), 68);
    });

    test('unmapped key returns null', () {
      // Fn key has no Android equivalent
      expect(androidKeycodeForPhysicalKey(PhysicalKeyboardKey.fn), isNull);
    });
  });
}
