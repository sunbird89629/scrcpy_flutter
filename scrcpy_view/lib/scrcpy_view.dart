/// Scrcpy protocol and embeddable Flutter widget for Android screen mirroring.
library;

// Re-export the pure-Dart protocol layer for convenience.
export 'package:scrcpy_client/scrcpy_client.dart';

// Flutter-specific additions.
export 'src/backends/scrcpy_video_backend.dart';
export 'src/nav_buttons.dart';
export 'src/scrcpy_keycode_flutter.dart';
export 'src/scrcpy_metastate_flutter.dart';
export 'src/scrcpy_proxy_server.dart';
export 'src/scrcpy_view_controller.dart';
export 'src/scrcpy_view.dart';
export 'src/scrcpy_websocket_server.dart';
