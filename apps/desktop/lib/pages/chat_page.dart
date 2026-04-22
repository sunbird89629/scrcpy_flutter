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

  @override
  void initState() {
    super.initState();
    player = Player();

    if (player.platform is NativePlayer) {
      final native = player.platform! as NativePlayer;
      native.setProperty('demuxer-lavf-format', 'h264');
      native.setProperty(
        'demuxer-lavf-o',
        'probesize=524288,analyzeduration=500000,fflags=+nobuffer+discardcorrupt',
      );
      native.setProperty('cache', 'no');
      native.setProperty('cache-pause', 'no');
      native.setProperty('low-latency', 'yes');
      native.setProperty('untimed', 'yes');
      native.setProperty('hr-seek', 'no');
      native.setProperty('video-latency-hacks', 'yes');
    }

    controller = VideoController(player);

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
    player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Video(
        controller: controller,
        controls: (state) => const SizedBox.shrink(),
      ),
    );
  }
}
