import 'package:autoglm_scrcpy_example/harness_controller.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class ScreenView extends StatelessWidget {
  const ScreenView({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = HarnessScope.of(context).videoController;
    return Expanded(
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.black,
          border: Border(left: BorderSide(color: Colors.white10, width: 2)),
        ),
        child: Center(
          child: controller == null || !controller.value.isInitialized
              ? const Text(
                  'No stream. Press Start.',
                  style: TextStyle(color: Colors.white54),
                )
              : AspectRatio(
                  aspectRatio: controller.value.aspectRatio,
                  child: VideoPlayer(controller),
                ),
        ),
      ),
    );
  }
}
