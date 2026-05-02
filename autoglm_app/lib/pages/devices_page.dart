import 'package:autoglm_app/i18n/strings.g.dart';
import 'package:autoglm_app/providers/adb_provider.dart';
import 'package:autoglm_app/providers/device_provider.dart';
import 'package:autoglm_app/theme/design_tokens.dart';
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
    final theme = Theme.of(context);

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
          const SizedBox(width: AppSpacing.sm),
        ],
      ),
      body: devicesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                size: 48,
                color: theme.colorScheme.error,
              ),
              const SizedBox(height: AppSpacing.md),
              Text('Error: $e'),
            ],
          ),
        ),
        data: (devices) {
          if (devices.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.devices_other,
                    size: 64,
                    color: theme.colorScheme.outline,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    t.devices_page.no_devices,
                    style: theme.textTheme.titleMedium,
                  ),
                ],
              ),
            );
          }
          return ListView.separated(
            padding: AppSpacing.edgeInsetsMd,
            itemCount: devices.length,
            separatorBuilder: (context, index) =>
                const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, index) {
              final id = devices[index];
              final isSelected = id == selectedId;
              return Card(
                elevation: isSelected ? 2 : 0,
                color: isSelected
                    ? theme.colorScheme.primaryContainer.withOpacity(0.3)
                    : theme.colorScheme.surfaceContainerLow,
                shape: RoundedRectangleBorder(
                  borderRadius: AppRadius.borderMd,
                  side: isSelected
                      ? BorderSide(color: theme.colorScheme.primary, width: 2)
                      : BorderSide(color: theme.colorScheme.outlineVariant),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.xs,
                  ),
                  leading: CircleAvatar(
                    backgroundColor: isSelected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.surfaceVariant,
                    child: Icon(
                      Icons.smartphone,
                      color: isSelected
                          ? theme.colorScheme.onPrimary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  title: Text(
                    id,
                    style: TextStyle(
                      fontWeight: isSelected ? FontWeight.bold : null,
                    ),
                  ),
                  subtitle: const Text('ADB Device'),
                  trailing: isSelected
                      ? Icon(
                          Icons.check_circle,
                          color: theme.colorScheme.primary,
                        )
                      : null,
                  onTap: () {
                    ref.read(selectedDeviceIdProvider.notifier).state = id;
                  },
                ),
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
        shape: RoundedRectangleBorder(borderRadius: AppRadius.borderLg),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: ipCtrl,
              decoration: InputDecoration(
                labelText: t.devices_page.ip,
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.network_wifi),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: portCtrl,
              decoration: InputDecoration(
                labelText: t.devices_page.port,
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.numbers),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: codeCtrl,
              decoration: InputDecoration(
                labelText: t.devices_page.code,
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.lock_outline),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final port = int.tryParse(portCtrl.text) ?? 0;
              try {
                final client = await ref.read(adbClientProvider.future);
                final res = await client.pair(ipCtrl.text, port, codeCtrl.text);
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(
                    ctx,
                  ).showSnackBar(SnackBar(content: Text(res)));
                  ref.invalidate(adbDevicesProvider);
                }
              } on Exception catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(
                    ctx,
                  ).showSnackBar(SnackBar(content: Text(e.toString())));
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
