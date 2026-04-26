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
import 'package:autoglm_scrcpy_example/harness_scope.dart';
import 'package:autoglm_scrcpy_example/screen_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_driver/driver_extension.dart';
import 'package:fvp/fvp.dart' as fvp;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Flip to false for the conservative path.
const kAggressive = true;

const kBufferMin = 0;

/// Buffer window in ms: 0 = aggressive, 50 = compromise, 200 = conservative.
const kBufferMax = 0;

Future<void> main() async {
  enableFlutterDriverExtension();
  // Root out library conflicts on macOS by ensuring we don't look in Homebrew.
  if (Platform.isMacOS) {
    // We can't easily change DYLD_LIBRARY_PATH from within the process (SIP),
    // but we can hint to plugins or log the state. 
    // A more effective way for mdk is to set the path before fvp.registerWith.
  }
  WidgetsFlutterBinding.ensureInitialized();

  final fvpOptions = <String, dynamic>{
    'video.decoders': _preferredDecoders(),
    'lowLatency': 1,
  };
  if (kAggressive) {
    // Disable ffmpeg demuxer probing and buffering
    fvpOptions['player.avformat.fflags'] = 'nobuffer';
    fvpOptions['player.avformat.flags'] = 'low_delay';
    fvpOptions['player.avformat.use_wallclock_as_timestamps'] = '1';
    fvpOptions['player.avformat.probesize'] = '32';
    fvpOptions['player.avformat.analyzeduration'] = '0';
    fvpOptions['player.avformat.fpsprobesize'] = '0';
    fvpOptions['player.avformat.max_delay'] = '0';
    fvpOptions['player.avformat.fflags'] = 'discardcorrupt+nobuffer'; // Extra aggressive
    fvpOptions['video.decoder.threads'] = '1';
    fvpOptions['video.decoder.async'] = '0'; // Sync decoding can be lower latency for single streams
    fvpOptions['video.decoder.buffer_range'] = '0-0'; // Force zero buffer at decoder level
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
    // Diagnostic: force FFmpeg to rule out VideoToolbox color-space mismatch.
    return ['FFmpeg'];
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
