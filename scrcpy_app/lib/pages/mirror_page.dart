import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scrcpy_app/providers/scrcpy_provider.dart';
import 'package:scrcpy_view/scrcpy_view.dart';

/// Main screen mirroring page with device selector and [ScrcpyView].
class MirrorPage extends ConsumerStatefulWidget {
  const MirrorPage({super.key});

  @override
  ConsumerState<MirrorPage> createState() => _MirrorPageState();
}

class _MirrorPageState extends ConsumerState<MirrorPage> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(devicesProvider.notifier).refresh());
  }

  @override
  Widget build(BuildContext context) {
    final devices = ref.watch(devicesProvider);
    final selectedId = ref.watch(selectedDeviceProvider);
    final mirrorState = ref.watch(mirrorStateProvider);

    return Column(
      children: [
        // Device selector bar
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              Expanded(
                child: devices.when(
                  data: (list) => DropdownButton<String>(
                    value: selectedId,
                    hint: const Text('Select device'),
                    isExpanded: true,
                    items: list
                        .map((d) => DropdownMenuItem(
                              value: d,
                              child: Text(d),
                            ))
                        .toList(),
                    onChanged: (id) {
                      if (id != null) {
                        ref.read(selectedDeviceProvider.notifier).state = id;
                      }
                    },
                  ),
                  loading: () => const CircularProgressIndicator(),
                  error: (e, _) => Text('Error: $e'),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: () =>
                    ref.read(devicesProvider.notifier).refresh(),
              ),
            ],
          ),
        ),

        // Mirror area
        Expanded(
          child: mirrorState.when(
            data: (adb) {
              if (adb == null || selectedId == null) {
                return const Center(
                  child: Text('Select a device to start mirroring'),
                );
              }
              return ScrcpyView(
                adb: adb,
                deviceId: selectedId,
                logger: ref.read(scrcpyLoggerProvider),
                onError: (err) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Scrcpy error: $err')),
                  );
                },
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
          ),
        ),
      ],
    );
  }
}
