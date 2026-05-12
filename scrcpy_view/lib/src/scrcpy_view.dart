import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:scrcpy_view/src/control_message.dart';
import 'package:scrcpy_view/src/scrcpy_keycode.dart';
import 'package:scrcpy_view/src/scrcpy_metastate.dart';
import 'package:scrcpy_view/src/scrcpy_view_controller.dart';
import 'package:scrcpy_view/webview_video_player.dart';

class ScrcpyView extends StatefulWidget {
  const ScrcpyView({required this.controller, super.key});

  final ScrcpyViewController controller;

  @override
  State<ScrcpyView> createState() => _ScrcpyViewState();
}

class _ScrcpyViewState extends State<ScrcpyView> {
  final _focusNode = FocusNode();
  final _metastate = ScrcpyMetastate();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent &&
        event is! KeyUpEvent &&
        event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final isDown = event is! KeyUpEvent;

    // Update modifier state (returns true if key is a modifier).
    _metastate.handleKey(event.logicalKey, isDown: isDown);

    final androidKeycode = androidKeycodeForPhysicalKey(event.physicalKey);
    if (androidKeycode == null) return KeyEventResult.ignored;

    widget.controller.sendControlMessage(
      ScrcpyInjectKeyMessage(
        action: isDown ? ScrcpyAction.down : ScrcpyAction.up,
        keycode: androidKeycode,
        metastate: _metastate.bitmask,
      ),
    );
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final server = widget.controller.server;
        if (server == null) {
          return const Center(child: Text('点击 Start 启动服务'));
        }
        return Focus(
          focusNode: _focusNode,
          onKeyEvent: _handleKeyEvent,
          autofocus: true,
          child: GestureDetector(
            onTap: _focusNode.requestFocus,
            child: WebViewVideoPlayer(
              playerUrl: server.playerUrl,
              touchController: widget.controller.touchController,
              onControlMessage: widget.controller.sendControlMessage,
            ),
          ),
        );
      },
    );
  }
}
