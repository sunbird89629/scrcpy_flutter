import 'dart:async';

import 'package:flutter/material.dart';
import 'package:scrcpy_view/src/backends/scrcpy_video_backend.dart';
import 'package:scrcpy_view/src/control_message.dart';
import 'package:scrcpy_view/src/scrcpy_adb.dart';
import 'package:scrcpy_view/src/scrcpy_logger.dart';
import 'package:scrcpy_view/src/scrcpy_server.dart';
import 'package:scrcpy_view/src/scrcpy_view_controller.dart';
import 'package:scrcpy_view/webview_video_player.dart';

/// A self-contained Flutter widget that mirrors an Android device screen
/// via the scrcpy protocol and accepts touch input.
class ScrcpyView extends StatefulWidget {
  const ScrcpyView({
    required this.adb,
    required this.deviceId,
    super.key,
    this.controller,
    this.logger = const NoOpScrcpyLogger(),
    this.onStarted,
    this.onStopped,
    this.onError,
  });

  /// ADB client for device communication.
  final ScrcpyAdb adb;

  /// Serial of the target Android device.
  final String deviceId;

  /// Optional controller for external lifecycle control and device input.
  ///
  /// When provided the controller exposes [ScrcpyViewController.start],
  /// [ScrcpyViewController.stop], [ScrcpyViewController.injectKey], and
  /// other APIs so callers do not need to manage state through callbacks.
  final ScrcpyViewController? controller;

  /// Logger for protocol and connection events.
  final ScrcpyLogger logger;

  /// Callback when mirroring starts.
  final VoidCallback? onStarted;

  /// Callback when mirroring stops.
  final VoidCallback? onStopped;

  /// Callback for errors during mirroring.
  final ValueChanged<String>? onError;

  @override
  State<ScrcpyView> createState() => _ScrcpyViewState();
}

class _ScrcpyViewState extends State<ScrcpyView> {
  ScrcpyServer? _server;
  late final ScrcpyTouchController _touchController;

  @override
  void initState() {
    super.initState();
    _touchController = ScrcpyTouchController((msg) {
      _server?.sendControlMessage(msg);
    });
    _start();
  }

  @override
  void dispose() {
    widget.controller?.detachServer();
    _stop();
    super.dispose();
  }

  Future<void> _start() async {
    if (_server != null) return;
    final server = ScrcpyServer(
      adb: widget.adb,
      deviceId: widget.deviceId,
      logger: widget.logger,
    );
    widget.controller?.attachServer(server, _restart);
    widget.controller?.markStarting();
    try {
      await server.start();
      if (!mounted) return;
      setState(() => _server = server);
      widget.controller?.markStarted();
      widget.onStarted?.call();
    } catch (e) {
      widget.logger.error('[ScrcpyView] Failed to start: $e', e);
      widget.controller?.markError(e.toString());
      if (mounted) widget.onError?.call(e.toString());
    }
  }

  Future<void> _restart() async {
    await _stop();
    if (mounted) await _start();
  }

  Future<void> _stop() async {
    await _server?.stop();
    _server = null;
    widget.controller?.markStopped();
    if (mounted) widget.onStopped?.call();
  }

  void _sendControl(ScrcpyControlMessage msg) {
    _server?.sendControlMessage(msg);
  }

  @override
  Widget build(BuildContext context) {
    final server = _server;
    if (server == null) {
      return const Center(child: CircularProgressIndicator());
    } else {
      const backend = WebViewVideoPlayer();
      return backend.build(
        playerUrl: server.playerUrl,
        touchController: _touchController,
        onControlMessage: _sendControl,
      );
    }
  }
}
