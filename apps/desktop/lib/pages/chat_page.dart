import 'package:autoglm_desktop/providers/scrcpy_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
          // Left side: Screen Stream Placeholder
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
                  return const _ScreenPlaceholder();
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

class _ScreenPlaceholder extends ConsumerWidget {
  const _ScreenPlaceholder();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metadataAsync = ref.watch(scrcpyMetadataProvider);

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.videocam, size: 64, color: Colors.white),
        const SizedBox(height: 16),
        metadataAsync.when(
          data: (meta) => Text(
            'Streaming: ${meta.deviceName} (${meta.width}x${meta.height})',
            style: const TextStyle(color: Colors.white),
          ),
          loading: () => const Text(
            'Waiting for metadata...',
            style: TextStyle(color: Colors.white70),
          ),
          error: (e, _) => Text(
            'Metadata error: $e',
            style: const TextStyle(color: Colors.redAccent),
          ),
        ),
      ],
    );
  }
}
