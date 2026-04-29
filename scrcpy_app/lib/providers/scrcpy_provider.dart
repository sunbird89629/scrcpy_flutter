import 'package:autoglm_adb/autoglm_adb.dart';
import 'package:autoglm_logger/autoglm_logger.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scrcpy_app/adapters/scrcpy_adapters.dart';
import 'package:scrcpy_view/scrcpy_view.dart';

/// Available ADB devices.
final devicesProvider = AsyncNotifierProvider<DevicesNotifier, List<String>>(
  DevicesNotifier.new,
);

class DevicesNotifier extends AsyncNotifier<List<String>> {
  @override
  Future<List<String>> build() async {
    final client = AdbClient();
    final devices = await client.listDevices();
    final list = devices.toList();
    if (list.isNotEmpty && ref.read(selectedDeviceProvider) == null) {
      Future.microtask(
        () => ref.read(selectedDeviceProvider.notifier).state = list.first,
      );
    }
    return list;
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final client = AdbClient();
      final devices = await client.listDevices();
      final list = devices.toList();
      if (list.isNotEmpty && ref.read(selectedDeviceProvider) == null) {
        ref.read(selectedDeviceProvider.notifier).state = list.first;
      }
      return list;
    });
  }
}

/// Currently selected device serial.
final selectedDeviceProvider = StateProvider<String?>((ref) => null);

/// Scrcpy ADB adapter for the selected device.
final mirrorStateProvider = AsyncNotifierProvider<MirrorNotifier, ScrcpyAdb?>(
  MirrorNotifier.new,
);

class MirrorNotifier extends AsyncNotifier<ScrcpyAdb?> {
  @override
  Future<ScrcpyAdb?> build() async {
    final selectedId = ref.watch(selectedDeviceProvider);
    if (selectedId == null) return null;
    return AdbClientAdapter(AdbClient());
  }
}

/// Shared [ScrcpyLogger] backed by `appLogger`.
final scrcpyLoggerProvider = Provider<ScrcpyLogger>((ref) {
  initAppLogger();
  return const AppLoggerAdapter();
});
