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
                error: (e, _) => Center(
                  child: Text(
                    'Error: $e',
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
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
    controller = VideoController(player);
    // Open FIFO file created by proxy server
    final url = 'file://${widget.server.proxyFifoPath}';
    print('[ChatPage] Opening video stream at $url');
    player.open(Media(url));
  }

  @override
  void dispose() {
    player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Video(
      controller: controller,
      controls: (state) => const SizedBox.shrink(),
    );
  }
}
