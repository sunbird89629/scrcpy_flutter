import 'package:autoglm_scrcpy_example/base_view.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class ScreenView extends BaseView {
  const ScreenView({super.key});

  @override
  Widget buildView(context, controller) {
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
