/// scrcpy preview harness that drives `fvp` (libmdk) with raw H.264
/// Annex-B, bypassing `media_kit` and MPEG-TS muxing entirely.
///
/// Run:
///   flutter run -d macos
library;

import 'dart:io';

import 'package:autoglm_core/autoglm_core.dart';
import 'package:autoglm_scrcpy_example/control_view.dart';
import 'package:autoglm_scrcpy_example/harness_controller.dart';
import 'package:autoglm_scrcpy_example/screen_view.dart';
import 'package:flutter/material.dart';
import 'package:fvp/fvp.dart' as fvp;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Flip to false for the conservative path.
const kAggressive = true;

const kBufferMin = 0;

/// Buffer window in ms: 0 = aggressive, 50 = compromise, 200 = conservative.
const kBufferMax = 0;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final fvpOptions = <String, dynamic>{
    'video.decoders': _preferredDecoders(),
    'lowLatency': 1,
  };
  if (kAggressive) {
    // Disable ffmpeg demuxer probing and buffering so the first frame
    // surfaces earlier.
    fvpOptions['player.avformat.fflags'] = 'nobuffer';
    fvpOptions['player.avformat.flags'] = 'low_delay';
    // Raw H.264 has no PTS — without this, the h264 demuxer fabricates
    // timestamps at a fixed (default 25) fps, which lags behind the device's
    // real frame rate and produces 5–10s of catch-up at startup.
    fvpOptions['player.avformat.use_wallclock_as_timestamps'] = '1';
    // Skip the multi-second probe/analyze phase before initialize() returns.
    fvpOptions['player.avformat.probesize'] = '32';
    fvpOptions['player.avformat.analyzeduration'] = '0';
  }
  fvp.registerWith(options: fvpOptions);

  final tempDir = await getTemporaryDirectory();
  initAppLogger(logsDir: p.join(tempDir.path, 'autoglm_logs'));

  runApp(
    const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: FvpScrcpyTestScreen(),
    ),
  );
}

List<String> _preferredDecoders() {
  if (Platform.isMacOS || Platform.isIOS) {
    return ['VT', 'FFmpeg'];
  }
  if (Platform.isWindows) {
    return ['MFT:d3d=11', 'D3D11', 'DXVA', 'CUDA', 'FFmpeg'];
  }
  if (Platform.isLinux) {
    return ['VAAPI', 'VDPAU', 'CUDA', 'FFmpeg'];
  }
  return ['FFmpeg'];
}

/// Root widget for the fvp-based scrcpy preview harness.
class FvpScrcpyTestScreen extends StatefulWidget {
  /// Creates the harness.
  const FvpScrcpyTestScreen({super.key});

  @override
  State<FvpScrcpyTestScreen> createState() => _FvpScrcpyTestScreenState();
}

class _FvpScrcpyTestScreenState extends State<FvpScrcpyTestScreen> {
  late final HarnessController _controller = HarnessController(
    aggressive: kAggressive,
    bufferMin: kBufferMin,
    bufferMax: kBufferMax,
  );

  String get _title => 'AutoGLM Scrcpy (fvp) — '
      '${kAggressive ? "aggressive" : "conservative"} '
      '[$kBufferMin,${kBufferMax}ms]';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return HarnessScope(
      controller: _controller,
      child: Scaffold(
        backgroundColor: const Color(0xFF1E1E1E),
        appBar: AppBar(
          title: Text(_title),
          backgroundColor: Colors.indigo[900],
          foregroundColor: Colors.white,
        ),
        body: const Row(
          children: [
            ScreenView(),
            ControlView(),
          ],
        ),
      ),
    );
  }
}
