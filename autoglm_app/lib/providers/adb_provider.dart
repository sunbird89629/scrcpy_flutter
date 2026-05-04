import 'package:adb_tools/adb_tools.dart';
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
  return AdbClientImpl(adbPath: adbPath);
});

/// Provider for the list of connected ADB devices.
final adbDevicesProvider = FutureProvider.autoDispose<List<String>>((
  ref,
) async {
  final client = await ref.watch(adbClientProvider.future);
  return client.getDevices();
});

/// Provider for the list of connected devices with rich info.
final adbDevicesWithInfoProvider =
    FutureProvider.autoDispose<List<DeviceInfo>>((ref) async {
  final client = await ref.watch(adbClientProvider.future);
  return client.getDevicesWithInfo();
});
