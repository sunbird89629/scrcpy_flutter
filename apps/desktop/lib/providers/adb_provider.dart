import 'package:autoglm_adb/autoglm_adb.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Provider for the [AdbClient].
final adbClientProvider = Provider<AdbClient>((ref) {
  // Uses default 'adb' in PATH for now.
  return const AdbClient();
});

/// Provider for the list of connected ADB devices.
final adbDevicesProvider =
    FutureProvider.autoDispose<List<String>>((ref) async {
  final client = ref.watch(adbClientProvider);
  return client.devices();
});
