import 'dart:convert';
import 'dart:typed_data';

import 'package:scrcpy_mcp/src/agent/screenshot_util.dart';
import 'package:test/test.dart';

void main() {
  group('blankRetryingScreenshot', () {
    Uint8List bytesOf(int n) => Uint8List.fromList(List.filled(n, 1));

    test('returns base64 of a valid (large enough) capture', () async {
      final provider = blankRetryingScreenshot(
        () async => bytesOf(50),
        minValidBytes: 10,
      );
      final shot = await provider();
      expect(shot.mimeType, 'image/png');
      expect(shot.base64, base64Encode(bytesOf(50)));
    });

    test('retries while blank, then returns the first valid frame', () async {
      var call = 0;
      final provider = blankRetryingScreenshot(
        () async => ++call < 3 ? bytesOf(1) : bytesOf(50),
        maxRetries: 3,
        minValidBytes: 10,
      );
      final shot = await provider();
      expect(call, 3);
      expect(shot.base64, base64Encode(bytesOf(50)));
    });

    test('throws when the capture stays empty (e.g. FLAG_SECURE)', () async {
      final provider = blankRetryingScreenshot(
        () async => Uint8List(0),
        maxRetries: 1,
        minValidBytes: 10,
      );
      await expectLater(provider(), throwsA(isA<StateError>()));
    });
  });
}
