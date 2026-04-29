import 'package:autoglm_adb/autoglm_adb.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Provider for the [AdbBinaryManager].
final adbBinaryManagerProvider = Provider<Future<AdbBinaryManager>>((
  ref,
) async {
  final appSupportDir = await getApplicationSupportDirectory();
  final binDir = p.join(appSupportDir.path, 'bin');
  return AdbBinaryManager(binDir: binDir);
});

/// Provider for the [AdbClient].
final adbClientProvider = FutureProvider<AdbClient>((ref) async {
  final manager = await ref.watch(adbBinaryManagerProvider);
  final adbPath = await manager.ensureAdb();
  return AdbClient(adbPath: adbPath);
});

/// Provider for the list of connected ADB devices.
final adbDevicesProvider = FutureProvider.autoDispose<List<String>>((
  ref,
) async {
  final client = await ref.watch(adbClientProvider.future);
  return client.devices();
});
