import 'package:autoglm_desktop/providers/adb_provider.dart';
import 'package:autoglm_desktop/providers/device_provider.dart';
import 'package:autoglm_scrcpy/autoglm_scrcpy.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Provider for a [ScrcpyServer] instance for the selected device.
final scrcpyServerProvider =
    FutureProvider.autoDispose<ScrcpyServer?>((ref) async {
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
final scrcpyMetadataProvider =
    StreamProvider.autoDispose<ScrcpyMetadata>((ref) {
  final serverAsync = ref.watch(scrcpyServerProvider);
  return serverAsync.when(
    data: (server) => server?.metadata ?? const Stream.empty(),
    error: (_, __) => const Stream.empty(),
    loading: () => const Stream.empty(),
  );
});
