import 'dart:async';

import 'package:flutter/material.dart';
import 'package:scrcpy_view/src/backends/scrcpy_video_backend.dart';
import 'package:scrcpy_view/src/control_message.dart';
import 'package:scrcpy_view/src/scrcpy_adb.dart';
import 'package:scrcpy_view/src/scrcpy_logger.dart';
import 'package:scrcpy_view/src/scrcpy_server.dart';

/// A self-contained Flutter widget that mirrors an Android device screen
/// via the scrcpy protocol and accepts touch input.
class ScrcpyView extends StatefulWidget {
  const ScrcpyView({
    super.key,
    required this.adb,
    required this.deviceId,
    this.logger = const NoOpScrcpyLogger(),
    this.videoBackend,
    this.onStarted,
    this.onStopped,
    this.onError,
  });

  /// ADB client for device communication.
  final ScrcpyAdb adb;

  /// Serial of the target Android device.
  final String deviceId;

  /// Logger for protocol and connection events.
  final ScrcpyLogger logger;

  /// Video rendering backend. Defaults to a simple placeholder.
  final ScrcpyVideoBackend? videoBackend;

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
    _stop();
    super.dispose();
  }

  Future<void> _start() async {
    try {
      final server = ScrcpyServer(
        adb: widget.adb,
        deviceId: widget.deviceId,
        logger: widget.logger,
      );
      await server.start();
      if (!mounted) return;
      setState(() => _server = server);
      widget.onStarted?.call();
    } catch (e) {
      widget.logger.error('[ScrcpyView] Failed to start: $e', e);
      if (mounted) widget.onError?.call(e.toString());
    }
  }

  Future<void> _stop() async {
    await _server?.stop();
    _server = null;
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
    }

    final backend = widget.videoBackend ?? _DefaultBackend();
    return backend.build(
      playerUrl: server.playerUrl,
      touchController: _touchController,
      onControlMessage: _sendControl,
    );
  }
}

/// Minimal default backend that shows the WebView URL.
class _DefaultBackend implements ScrcpyVideoBackend {
  @override
  Widget build({
    required String playerUrl,
    required ScrcpyTouchController touchController,
    required void Function(ScrcpyControlMessage) onControlMessage,
  }) {
    return Center(
      child: Text('Player URL: $playerUrl'),
    );
  }
}
