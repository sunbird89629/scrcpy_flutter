import 'package:flutter/material.dart';
import 'package:scrcpy_view/src/scrcpy_view_controller.dart';
import 'package:scrcpy_view/webview_video_player.dart';

class ScrcpyView extends StatelessWidget {
  const ScrcpyView({required this.controller, super.key});

  /// Controller that owns the mirroring session and exposes input injection.
  final ScrcpyViewController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final server = controller.server;
        debugPrint('ScrcpyView.playerUrl:${server?.playerUrl}');
        if (server == null) {
          return const Center(child: Text('点击 Start 启动服务'));
        } else {
          return WebViewVideoPlayer(
            playerUrl: server.playerUrl,
            touchController: controller.touchController,
            onControlMessage: controller.sendControlMessage,
          );
        }
      },
    );
  }
}
