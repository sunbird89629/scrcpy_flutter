import 'package:flutter/material.dart';
import 'package:scrcpy_view/src/scrcpy_view_controller.dart';
import 'package:scrcpy_view/webview_video_player.dart';

/// A self-contained Flutter widget that mirrors an Android device screen
/// via the scrcpy protocol and accepts touch input.
///
/// Rendering is driven by [controller]: pass the same instance to
/// [ScrcpyViewController.start] and this widget. The widget rebuilds
/// automatically when the session state changes.
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
        if (server == null) {
          return const Center(child: Text('点击 Start 启动服务'));
        }
        const backend = WebViewVideoPlayer();
        return backend.build(
          playerUrl: server.playerUrl,
          touchController: controller.touchController,
          onControlMessage: controller.sendControlMessage,
        );
      },
    );
  }
}
