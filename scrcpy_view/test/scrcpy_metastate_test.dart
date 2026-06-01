import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_view/scrcpy_view.dart';

void main() {
  group('ScrcpyMetastate', () {
    late ScrcpyMetastate metastate;

    setUp(() {
      metastate = ScrcpyMetastate();
    });

    test('initial bitmask is 0', () {
      expect(metastate.bitmask, 0);
    });

    test('shift produces 0x1', () {
      metastate.handleKey(LogicalKeyboardKey.shiftLeft, isDown: true);
      expect(metastate.bitmask, AndroidMetastate.shiftOn);
    });

    test('alt produces 0x2', () {
      metastate.handleKey(LogicalKeyboardKey.altLeft, isDown: true);
      expect(metastate.bitmask, AndroidMetastate.altOn);
    });

    test('ctrl produces 0x1000', () {
      metastate.handleKey(LogicalKeyboardKey.controlLeft, isDown: true);
      expect(metastate.bitmask, AndroidMetastate.ctrlOn);
    });

    test('meta produces 0x10000', () {
      metastate.handleKey(LogicalKeyboardKey.metaLeft, isDown: true);
      expect(metastate.bitmask, AndroidMetastate.metaOn);
    });

    test('combined modifiers OR correctly', () {
      metastate.handleKey(LogicalKeyboardKey.shiftLeft, isDown: true);
      metastate.handleKey(LogicalKeyboardKey.controlLeft, isDown: true);
      expect(
        metastate.bitmask,
        AndroidMetastate.shiftOn | AndroidMetastate.ctrlOn,
      );
    });

    test('releasing modifier clears the bit', () {
      metastate.handleKey(LogicalKeyboardKey.shiftLeft, isDown: true);
      expect(metastate.bitmask, AndroidMetastate.shiftOn);
      metastate.handleKey(LogicalKeyboardKey.shiftLeft, isDown: false);
      expect(metastate.bitmask, 0);
    });

    test('handleKey returns true for modifier keys', () {
      expect(
        metastate.handleKey(LogicalKeyboardKey.shift, isDown: true),
        isTrue,
      );
      expect(
        metastate.handleKey(LogicalKeyboardKey.altRight, isDown: true),
        isTrue,
      );
      expect(
        metastate.handleKey(LogicalKeyboardKey.control, isDown: true),
        isTrue,
      );
      expect(
        metastate.handleKey(LogicalKeyboardKey.metaRight, isDown: true),
        isTrue,
      );
    });

    test('handleKey returns false for non-modifier keys', () {
      expect(
        metastate.handleKey(LogicalKeyboardKey.keyA, isDown: true),
        isFalse,
      );
      expect(
        metastate.handleKey(LogicalKeyboardKey.enter, isDown: true),
        isFalse,
      );
      expect(
        metastate.handleKey(LogicalKeyboardKey.arrowUp, isDown: true),
        isFalse,
      );
    });

    test('releasing one modifier preserves others', () {
      metastate.handleKey(LogicalKeyboardKey.shiftLeft, isDown: true);
      metastate.handleKey(LogicalKeyboardKey.altLeft, isDown: true);
      metastate.handleKey(LogicalKeyboardKey.shiftLeft, isDown: false);
      expect(metastate.bitmask, AndroidMetastate.altOn);
    });
  });
}
