import 'package:autoglm_desktop/providers/adb_provider.dart';
import 'package:autoglm_desktop/providers/device_provider.dart';
import 'package:autoglm_scrcpy/autoglm_scrcpy.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Provider for a [ScrcpyServer] instance for the selected device.
final scrcpyServerProvider = FutureProvider<ScrcpyServer?>((ref) async {
  final deviceId = ref.watch(selectedDeviceIdProvider);
  if (deviceId == null) return null;

  final adbClient = await ref.watch(adbClientProvider.future);
  final server = ScrcpyServer(adbClient: adbClient, deviceId: deviceId);

  ref.onDispose(() async {
    await server.stop();
  });

  await server.start();
  return server;
});

/// Provider for scrcpy metadata.
final scrcpyMetadataProvider = StreamProvider<ScrcpyMetadata>((ref) async* {
  final server = await ref.watch(scrcpyServerProvider.future);
  if (server == null) return;

  // The parser emits metadata on a broadcast stream exactly once during
  // server start-up — often before this provider has subscribed. Replay the
  // cached value so the UI can render immediately instead of spinning.
  final cached = server.currentMetadata;
  if (cached != null) yield cached;
  yield* server.metadata;
});
