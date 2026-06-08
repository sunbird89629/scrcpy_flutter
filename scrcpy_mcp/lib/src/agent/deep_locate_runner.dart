import 'dart:convert';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'llm_client.dart';
import 'response_parser.dart';

/// Wraps an [ActionRunner] with two-pass deep-locate refinement for Tap actions
/// (inspired by Midscene's deepLocate).
///
/// **How it works:**
///   Pass 1 – model returns `Tap [x,y]` on full screenshot (~49px error).
///   Pass 2 – crop around [x,y] and re-ask the model on the zoomed-in view.
///   Map the refined coordinate back to full-screen space and execute.
///
/// Non-Tap actions pass through unchanged.
class DeepLocateActionRunner {
  DeepLocateActionRunner({
    required this.inner,
    required this.screenshotProvider,
    required this.chat,
    this.cropRadius = 150, // model-coord radius (0–1000)
    this.enabled = true,
  });

  final Future<String> Function(PhoneAction) inner;
  final Future<Uint8List> Function() screenshotProvider;
  final ChatFn chat;
  final int cropRadius;
  final bool enabled;

  /// Matches [ActionRunner] so this can be passed directly.
  Future<String> run(PhoneAction action) async {
    if (!enabled) return inner(action);
    if (action is! DoAction) return inner(action);
    if (action.action != 'Tap') return inner(action);
    final coords = action.element;
    if (coords == null || coords.length < 2) return inner(action);

    final refined = await _deepLocate(x: coords[0], y: coords[1]);

    if (refined == null) return inner(action);

    final refinedAction = DoAction(
      action: action.action,
      element: [refined.x, refined.y],
      text: action.text,
      app: action.app,
      message: action.message,
      duration: action.duration,
    );
    return inner(refinedAction);
  }

  /// Returns refined full-screen [0,1000] coordinate, or null to fall back.
  Future<({int x, int y})?> _deepLocate({
    required int x,
    required int y,
  }) async {
    try {
      // 1. Take current screenshot
      final fullBytes = await screenshotProvider();
      if (fullBytes.isEmpty) return null;

      // 2. Decode and crop
      final fullImage = img.decodePng(fullBytes);
      if (fullImage == null) return null;

      final imgW = fullImage.width;
      final imgH = fullImage.height;

      // Model → pixel
      final pxX = (x * imgW / 1000).round();
      final pxY = (y * imgH / 1000).round();
      final pxRadius = (cropRadius * imgW / 1000).round();

      final x1 = (pxX - pxRadius).clamp(0, imgW - 1);
      final y1 = (pxY - pxRadius).clamp(0, imgH - 1);
      final x2 = (pxX + pxRadius).clamp(x1 + 1, imgW);
      final y2 = (pxY + pxRadius).clamp(y1 + 1, imgH);

      final cropped = img.copyCrop(
        fullImage,
        x: x1,
        y: y1,
        width: x2 - x1,
        height: y2 - y1,
      );
      final cropBytes = Uint8List.fromList(img.encodePng(cropped));

      // 3. Ask model for refined coordinate in cropped view [0,1000]
      final base64Crop = base64Encode(cropBytes);
      final response = await chat(
        messages: [
          LlmMessage(
            role: 'user',
            textContent:
                '这是之前定位区域的放大视图。'
                '请用 do(action="Tap", element=[x,y]) 返回目标元素在当前视图中的精确中心坐标。'
                '坐标空间 [0,1000]。只返回单独一行 do(...)。',
            imageBase64: base64Crop,
            imageMimeType: 'image/png',
          ),
        ],
      );

      final refined = _parseTapCoord(response.text ?? '');
      if (refined == null) return null;

      // 4. Map local crop coord → full-screen model coord
      final fullX = x1 + (refined.x * (x2 - x1) / 1000).round();
      final fullY = y1 + (refined.y * (y2 - y1) / 1000).round();

      // Convert pixel → model [0,1000]
      return (
        x: (fullX * 1000 / imgW).round().clamp(0, 1000),
        y: (fullY * 1000 / imgH).round().clamp(0, 1000),
      );
    } catch (_) {
      return null; // Fall back to original coordinate
    }
  }
}

/// Parse "do(action="Tap", element=[x,y])" → (x,y) or null.
({int x, int y})? _parseTapCoord(String raw) {
  final m = RegExp(r'element\s*=\s*\[(\d+)\s*,\s*(\d+)\]').firstMatch(raw);
  if (m == null) return null;
  return (x: int.parse(m.group(1)!), y: int.parse(m.group(2)!));
}
