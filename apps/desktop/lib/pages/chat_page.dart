import 'dart:async';

import 'package:autoglm_core/autoglm_core.dart';
import 'package:autoglm_desktop/providers/scrcpy_provider.dart';
import 'package:autoglm_scrcpy/autoglm_scrcpy.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// Page for chat and screen streaming.
class ChatPage extends ConsumerWidget {
  /// Creates a [ChatPage].
  const ChatPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scrcpyAsync = ref.watch(scrcpyServerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat & Screen'),
      ),
      body: Row(
        children: [
          // Left side: Screen Stream
          Expanded(
            child: ColoredBox(
              color: Colors.black,
              child: scrcpyAsync.when(
                data: (server) {
                  if (server == null) {
                    return const Center(
                      child: Text(
                        'No device selected',
                        style: TextStyle(color: Colors.white),
                      ),
                    );
                  }
                  return _ScreenView(server: server);
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, st) {
                  appLogger.e('scrcpyServerProvider error', e, st);
                  return Center(
                    child: Text(
                      'Error: $e',
                      style: const TextStyle(color: Colors.red),
                    ),
                  );
                },
              ),
            ),
          ),
          const VerticalDivider(width: 1),
          // Right side: Chat Placeholder
          const Expanded(
            child: Center(
              child: Text('Chat Implementation Placeholder'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScreenView extends StatefulWidget {
  const _ScreenView({required this.server});
  final ScrcpyServer server;

  @override
  State<_ScreenView> createState() => _ScreenViewState();
}

class _ScreenViewState extends State<_ScreenView> {
  late final Player player;
  late final VideoController controller;
  StreamSubscription<dynamic>? _errorSubscription;
  StreamSubscription<dynamic>? _videoParamsSubscription;
  StreamSubscription<dynamic>? _logSubscription;

  @override
  void initState() {
    super.initState();
    // STEP 1: minimal config to verify basic playback
    player = Player();

    // 2. Setup Native properties for raw H264 stream
    if (player.platform is NativePlayer) {
      final native = player.platform! as NativePlayer;

      // NOTE: bundled mpv's ffmpeg is trimmed and doesn't expose the `h264`
      // demuxer by name. Leave demuxer auto-probe on.

      // Disable audio to prevent mp3float or other audio probing errors
      native.setProperty('aid', 'no');

      // tcp:// URLs are treated as playlist entries by mpv and blocked
      // unless explicitly allowed.
      native.setProperty('load-unsafe-playlists', 'yes');

      // Low-latency live playback: render frames as they arrive rather
      // than waiting for their PTS, drop all demuxer/stream buffering.
      native.setProperty('untimed', 'yes');
      native.setProperty('cache', 'no');
      native.setProperty('demuxer-readahead-secs', '0');
      native.setProperty('video-latency-hacks', 'yes');
      native.setProperty('video-sync', 'desync');

      // Qualcomm's c2.qti.avc.encoder tags the H.264 VUI as ycgco; under
      // hardware decoding mpv's shader picks a wrong matrix and the image
      // goes red. Force BT.709 via mpv's native `format` filter.
      native.setProperty('vf', 'format=colormatrix=bt.709');

      // Verbose mpv logging for diagnosis
      native.setProperty('msg-level', 'all=v');
    }

    _errorSubscription = player.stream.error.listen((error) {
      appLogger.e('[ChatPage] Player Error: $error');
    });

    _videoParamsSubscription = player.stream.videoParams.listen((params) {
      appLogger.i(
        '[ChatPage] Video Params: ${params.w}x${params.h} aspect=${params.aspect}',
      );
    });

    _logSubscription = player.stream.log.listen((e) {
      appLogger.d('[mpv][${e.prefix}][${e.level}] ${e.text}');
    });

    // 3. Create VideoController (HW accel is on by default on macOS).
    controller = VideoController(player);

    // 4. Open the stream when proxy is ready
    final url = widget.server.proxyUrl;
    appLogger.i('[ChatPage] Waiting for scrcpy proxy to be ready…');
    widget.server.proxyReady.then(
      (_) {
        if (!mounted) return;
        appLogger.i('[ChatPage] Opening media at $url');
        player.open(Media(url));
      },
      onError: (Object e, StackTrace st) {
        appLogger.e('[ChatPage] Proxy never became ready', e, st);
      },
    );
  }

  @override
  void dispose() {
    _errorSubscription?.cancel();
    _videoParamsSubscription?.cancel();
    _logSubscription?.cancel();
    player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, child) {
        final metadataAsync = ref.watch(scrcpyMetadataProvider);

        return metadataAsync.when(
          data: (meta) {
            final aspectRatio = (meta.width > 0 && meta.height > 0)
                ? meta.width / meta.height
                : 9 / 16;

            return Center(
              child: AspectRatio(
                aspectRatio: aspectRatio,
                child: Video(
                  controller: controller,
                  controls: (state) => const SizedBox.shrink(),
                  fill: Colors.transparent,
                ),
              ),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, st) => Center(child: Text('Metadata Error: $e')),
        );
      },
    );
  }
}
