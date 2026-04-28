/// scrcpy preview harness that drives `fvp` (libmdk) with raw H.264
/// Annex-B, bypassing `media_kit` and MPEG-TS muxing entirely.
///
/// Run:
///   flutter run -d macos

import 'dart:io';

import 'package:autoglm_core/autoglm_core.dart';
import 'package:autoglm_scrcpy_example/fpv/control_panel.dart';
import 'package:autoglm_scrcpy_example/fpv/fpv_controller.dart';
import 'package:autoglm_scrcpy_example/fpv/fpv_scope.dart';
import 'package:autoglm_scrcpy_example/fpv/video_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_driver/driver_extension.dart';
import 'package:fvp/fvp.dart' as fvp;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

const kAggressive = true;
const kBufferMin = 0;

/// Buffer window in ms: 0 = aggressive, 50 = compromise, 200 = conservative.
const kBufferMax = 0;

Future<void> launchFpv() async {
  enableFlutterDriverExtension();
  WidgetsFlutterBinding.ensureInitialized();

  final fvpOptions = <String, dynamic>{
    'video.decoders': _preferredDecoders(),
    'lowLatency': 1,
  };
  if (kAggressive) {
    fvpOptions['player.avformat.fflags'] = 'nobuffer';
    fvpOptions['player.avformat.flags'] = 'low_delay';
    fvpOptions['player.avformat.use_wallclock_as_timestamps'] = '1';
    fvpOptions['player.avformat.probesize'] = '32';
    fvpOptions['player.avformat.analyzeduration'] = '0';
    fvpOptions['player.avformat.fpsprobesize'] = '0';
    fvpOptions['player.avformat.max_delay'] = '0';
    fvpOptions['player.avformat.fflags'] = 'discardcorrupt+nobuffer';
    fvpOptions['video.decoder.threads'] = '1';
    fvpOptions['video.decoder.async'] = '0';
    fvpOptions['video.decoder.buffer_range'] = '0-0';
  }
  fvp.registerWith(options: fvpOptions);

  final tempDir = await getTemporaryDirectory();
  initAppLogger(logsDir: p.join(tempDir.path, 'autoglm_logs'));

  runApp(
    const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: FpvScreen(),
    ),
  );
}

List<String> _preferredDecoders() {
  if (Platform.isMacOS || Platform.isIOS) {
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

class FpvScreen extends StatefulWidget {
  const FpvScreen({super.key});

  @override
  State<FpvScreen> createState() => _FpvScreenState();
}

class _FpvScreenState extends State<FpvScreen> {
  late final FpvController _controller = FpvController(
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
    return FpvScope(
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
            VideoPanel(),
            ControlPanel(),
          ],
        ),
      ),
    );
  }
}
