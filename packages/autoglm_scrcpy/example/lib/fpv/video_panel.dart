import 'package:autoglm_scrcpy_example/fpv/fpv_scope.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class VideoPanel extends StatelessWidget {
  const VideoPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = FpvScope.of(context);
    final videoController = controller.videoController;
    return Expanded(
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.black,
          border: Border(left: BorderSide(color: Colors.white10, width: 2)),
        ),
        child: Center(
          child: videoController == null || !videoController.value.isInitialized
              ? const Text(
                  'No stream. Press Start.',
                  style: TextStyle(color: Colors.white54),
                )
              : AspectRatio(
                  aspectRatio: videoController.value.aspectRatio,
                  child: VideoPlayer(videoController),
                ),
        ),
      ),
    );
  }
}
