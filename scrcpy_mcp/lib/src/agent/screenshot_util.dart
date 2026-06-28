import 'dart:convert';
import 'dart:typed_data';

import 'phone_agent.dart' show ScreenshotProvider;

/// A real 1080-wide screencap is tens to hundreds of KB; a FLAG_SECURE / blank
/// screen encodes to a near-empty PNG. Below this byte size we treat the
/// screenshot as blank and retry rather than feed the model a black frame.
const kBlankScreenshotBytes = 20000;

/// Builds a [ScreenshotProvider] that fetches a PNG via [takeRaw], retrying up
/// to [maxRetries] times (1s apart) while the result is smaller than
/// [minValidBytes] (i.e. still looks blank), then returns it base64-encoded.
/// Shared by run_task and the real-device test runner so the blank-frame
/// heuristic stays in one place.
ScreenshotProvider blankRetryingScreenshot(
  Future<Uint8List> Function() takeRaw, {
  int maxRetries = 2,
  int minValidBytes = kBlankScreenshotBytes,
}) {
  return () async {
    var bytes = await takeRaw();
    for (var i = 0; i < maxRetries && bytes.length < minValidBytes; i++) {
      await Future<void>.delayed(const Duration(seconds: 1));
      bytes = await takeRaw();
    }
    // `adb exec-out screencap` exits 0 with empty stdout when the foreground
    // screen is FLAG_SECURE (e.g. DRM video). Encoding that yields an empty
    // base64, which strict vision APIs reject ("Invalid base64 image_url").
    // Fail loudly instead of sending a malformed request.
    if (bytes.isEmpty) {
      throw StateError(
        'screencap returned no data after ${maxRetries + 1} attempt(s); the '
        'foreground screen is likely FLAG_SECURE (e.g. DRM video) and cannot '
        'be captured via adb.',
      );
    }
    return (base64: base64Encode(bytes), mimeType: 'image/png');
  };
}
