import 'package:autoglm_app/providers/adb_provider.dart';
import 'package:autoglm_app/providers/device_provider.dart';
import 'package:autoglm_app/scrcpy/autoglm_scrcpy_bridge.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scrcpy_view/scrcpy_view.dart';

/// Provider for a [ScrcpyServer] instance for the selected device.
final scrcpyServerProvider = FutureProvider<ScrcpyServer?>((ref) async {
  final deviceId = ref.watch(selectedDeviceIdProvider);
  if (deviceId == null) return null;

  final adbClient = await ref.watch(adbClientProvider.future);
  final server = ScrcpyServer(
    adb: AutoGlmScrcpyAdb(adbClient),
    deviceId: deviceId,
    logger: const AutoGlmScrcpyLogger(),
  );

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

  final cached = server.currentMetadata;
  if (cached != null) yield cached;
  yield* server.metadata;
});
