import 'dart:async';

import 'package:autoglm_logger/autoglm_logger.dart';
import 'package:autoglm_app/providers/scrcpy_provider.dart';
import 'package:scrcpy_view/scrcpy_view.dart';
import 'package:autoglm_app/theme/design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

final _log = Logger('autoglm.app.ChatPage');

/// Page for chat and screen streaming.
class ChatPage extends ConsumerWidget {
  /// Creates a [ChatPage].
  const ChatPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scrcpyAsync = ref.watch(scrcpyServerProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat & Screen'),
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
      ),
      body: Row(
        children: [
          // Left side: Screen Stream
          Expanded(
            flex: 3,
            child: Container(
              margin: AppSpacing.edgeInsetsMd,
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: AppRadius.borderLg,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: scrcpyAsync.when(
                data: (server) {
                  if (server == null) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.smartphone,
                            size: 64,
                            color: Colors.white.withOpacity(0.3),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          const Text(
                            'No device selected',
                            style: TextStyle(color: Colors.white70),
                          ),
                        ],
                      ),
                    );
                  }
                  return _ScreenView(server: server);
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, st) {
                  _log.severe('scrcpyServerProvider error', e, st);
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
          VerticalDivider(
            width: 1,
            thickness: 1,
            color: theme.colorScheme.outlineVariant,
          ),
          // Right side: Chat Placeholder
          Expanded(
            flex: 2,
            child: Padding(
              padding: AppSpacing.edgeInsetsMd,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Assistant',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerLow,
                        borderRadius: AppRadius.borderMd,
                      ),
                      child: const Center(
                        child: Text('Chat Implementation Placeholder'),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    decoration: InputDecoration(
                      hintText: 'Ask AutoGLM to do something...',
                      suffixIcon: const Icon(Icons.send),
                      border: OutlineInputBorder(
                        borderRadius: AppRadius.borderMd,
                      ),
                    ),
                  ),
                ],
              ),
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
    player = Player();

    if (player.platform is NativePlayer) {
      final native = player.platform! as NativePlayer;
      native.setProperty('aid', 'no');
      native.setProperty('load-unsafe-playlists', 'yes');
      native.setProperty('untimed', 'yes');
      native.setProperty('cache', 'no');
      native.setProperty('demuxer-readahead-secs', '0');
      native.setProperty('video-latency-hacks', 'yes');
      native.setProperty('video-sync', 'desync');
      native.setProperty('vf', 'format=colormatrix=bt.709');
      native.setProperty('msg-level', 'all=v');
    }

    _errorSubscription = player.stream.error.listen((error) {
      _log.severe('Player Error: $error');
    });

    _videoParamsSubscription = player.stream.videoParams.listen((params) {
      _log.info(
        'Video Params: ${params.w}x${params.h} aspect=${params.aspect}',
      );
    });

    _logSubscription = player.stream.log.listen((e) {
      _log.fine('[mpv][${e.prefix}][${e.level}] ${e.text}');
    });

    controller = VideoController(player);

    final url = widget.server.proxyUrl;
    _log.info('Waiting for scrcpy proxy to be ready…');
    widget.server.proxyReady.then(
      (_) {
        if (!mounted) return;
        _log.info('Opening media at $url');
        player.open(Media(url));
      },
      onError: (Object e, StackTrace st) {
        _log.severe('Proxy never became ready', e, st);
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
