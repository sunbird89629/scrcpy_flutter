import 'package:autoglm_desktop/i18n/strings.g.dart';
import 'package:autoglm_desktop/providers/adb_provider.dart';
import 'package:autoglm_desktop/providers/device_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Page for managing connected ADB devices.
class DevicesPage extends ConsumerWidget {
  /// Creates a [DevicesPage].
  const DevicesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devicesAsync = ref.watch(adbDevicesProvider);
    final selectedId = ref.watch(selectedDeviceIdProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(t.nav.devices),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: t.devices_page.refresh,
            onPressed: () {
              ref.invalidate(adbDevicesProvider);
            },
          ),
          IconButton(
            icon: const Icon(Icons.add_link),
            tooltip: t.devices_page.pair_device,
            onPressed: () => _showPairDialog(context, ref),
          ),
        ],
      ),
      body: devicesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (devices) {
          if (devices.isEmpty) {
            return Center(child: Text(t.devices_page.no_devices));
          }
          return ListView.builder(
            itemCount: devices.length,
            itemBuilder: (context, index) {
              final id = devices[index];
              final isSelected = id == selectedId;
              return ListTile(
                leading: const Icon(Icons.smartphone),
                title: Text(id),
                selected: isSelected,
                trailing: isSelected ? const Icon(Icons.check_circle) : null,
                onTap: () {
                  ref.read(selectedDeviceIdProvider.notifier).state = id;
                },
              );
            },
          );
        },
      ),
    );
  }

  void _showPairDialog(BuildContext context, WidgetRef ref) {
    final ipCtrl = TextEditingController();
    final portCtrl = TextEditingController();
    final codeCtrl = TextEditingController();

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.devices_page.pair_device),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: ipCtrl,
              decoration: InputDecoration(labelText: t.devices_page.ip),
            ),
            TextField(
              controller: portCtrl,
              decoration: InputDecoration(labelText: t.devices_page.port),
            ),
            TextField(
              controller: codeCtrl,
              decoration: InputDecoration(labelText: t.devices_page.code),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final port = int.tryParse(portCtrl.text) ?? 0;
              try {
                final client = await ref.read(adbClientProvider.future);
                final res = await client.pair(ipCtrl.text, port, codeCtrl.text);
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(content: Text(res)),
                  );
                  ref.invalidate(adbDevicesProvider);
                }
              } on Exception catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(content: Text(e.toString())),
                  );
                }
              }
            },
            child: const Text('Pair'),
          ),
        ],
      ),
    );
  }
}
