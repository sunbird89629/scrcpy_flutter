import 'package:autoglm_adb/autoglm_adb.dart';
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
    final devicesAsync = ref.watch(adbDevicesWithInfoProvider);
    final selectedId = ref.watch(selectedDeviceIdProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(t.nav.devices),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: t.devices_page.refresh,
            onPressed: () => ref.invalidate(adbDevicesWithInfoProvider),
          ),
          IconButton(
            icon: const Icon(Icons.add_link),
            tooltip: t.devices_page.pair_device,
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => const _ConnectPairDialog(),
            ),
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
              Icon(Icons.error_outline, size: 48,
                  color: theme.colorScheme.error),
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
                  Icon(Icons.devices_other, size: 64,
                      color: theme.colorScheme.outline),
                  const SizedBox(height: AppSpacing.md),
                  Text(t.devices_page.no_devices,
                      style: theme.textTheme.titleMedium),
                ],
              ),
            );
          }
          return ListView.separated(
            padding: AppSpacing.edgeInsetsMd,
            itemCount: devices.length,
            separatorBuilder: (_, __) =>
                const SizedBox(height: AppSpacing.sm),
            itemBuilder: (_, index) {
              final info = devices[index];
              return _DeviceCard(
                info: info,
                isSelected: info.serial == selectedId,
                onTap: () => ref
                    .read(selectedDeviceIdProvider.notifier)
                    .state = info.serial,
              );
            },
          );
        },
      ),
    );
  }

}

// ---------------------------------------------------------------------------
// Private widgets
// ---------------------------------------------------------------------------

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({
    required this.info,
    required this.isSelected,
    required this.onTap,
  });

  final DeviceInfo info;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
              : theme.colorScheme.surfaceContainerHighest,
          child: Icon(
            Icons.smartphone,
            color: isSelected
                ? theme.colorScheme.onPrimary
                : theme.colorScheme.onSurfaceVariant,
          ),
        ),
        title: Text(
          info.displayName,
          style: TextStyle(
              fontWeight: isSelected ? FontWeight.bold : null),
        ),
        subtitle: _CardSubtitle(info: info),
        trailing: _StatusBadge(status: info.status),
        onTap: onTap,
      ),
    );
  }
}

class _CardSubtitle extends StatelessWidget {
  const _CardSubtitle({required this.info});
  final DeviceInfo info;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasDetails =
        info.manufacturer != null || info.androidVersion != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasDetails)
          Text(_detailLine(), style: theme.textTheme.bodySmall),
        Row(
          children: [
            Flexible(
              child: Text(
                info.serial,
                style: theme.textTheme.bodySmall,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Icon(
              info.isWifi ? Icons.wifi : Icons.usb,
              size: 14,
              color: theme.colorScheme.outline,
            ),
          ],
        ),
      ],
    );
  }

  String _detailLine() {
    final parts = <String>[];
    if (info.manufacturer != null) parts.add(info.manufacturer!);
    if (info.androidVersion != null) {
      final sdk =
          info.sdkVersion != null ? ' (API ${info.sdkVersion})' : '';
      parts.add('Android ${info.androidVersion}$sdk');
    }
    return parts.join(' · ');
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
  final DeviceStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return switch (status) {
      DeviceStatus.online => _badge(
          theme, Icons.circle, 10, theme.colorScheme.primary, 'online'),
      DeviceStatus.offline => _badge(
          theme, Icons.circle_outlined, 10, theme.colorScheme.outline,
          'offline'),
      DeviceStatus.unauthorized => _badge(
          theme, Icons.warning_amber, 14, theme.colorScheme.error,
          'unauthorized'),
    };
  }

  Widget _badge(ThemeData theme, IconData icon, double size, Color color,
      String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: size, color: color),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(fontSize: 12, color: color)),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Connect / Pair dialog
// ---------------------------------------------------------------------------

enum _DialogStep { connect, pair }

class _ConnectPairDialog extends ConsumerStatefulWidget {
  const _ConnectPairDialog();

  @override
  ConsumerState<_ConnectPairDialog> createState() =>
      _ConnectPairDialogState();
}

class _ConnectPairDialogState extends ConsumerState<_ConnectPairDialog> {
  _DialogStep _step = _DialogStep.connect;
  bool _isLoading = false;

  final _ipCtrl = TextEditingController();
  final _portCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();

  @override
  void dispose() {
    _ipCtrl.dispose();
    _portCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(t.devices_page.connect_device),
      shape: RoundedRectangleBorder(borderRadius: AppRadius.borderLg),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_step == _DialogStep.pair)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: Text(
                t.devices_page.not_paired_hint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.secondary,
                ),
              ),
            ),
          TextField(
            controller: _ipCtrl,
            enabled: !_isLoading,
            decoration: InputDecoration(
              labelText: t.devices_page.ip,
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.network_wifi),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _portCtrl,
            enabled: !_isLoading,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: t.devices_page.port,
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.numbers),
            ),
          ),
          if (_step == _DialogStep.pair) ...[
            const SizedBox(height: AppSpacing.md),
            TextField(
              key: const Key('code_field'),
              controller: _codeCtrl,
              enabled: !_isLoading,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: t.devices_page.code,
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.lock_outline),
              ),
            ),
          ],
        ],
      ),
      actions: [
        if (_isLoading)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: CircularProgressIndicator(),
          )
        else ...[
          if (_step == _DialogStep.pair)
            TextButton(
              onPressed: () => setState(() {
                _step = _DialogStep.connect;
                _codeCtrl.clear();
              }),
              child: Text(t.devices_page.back),
            )
          else
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          FilledButton(
            onPressed:
                _step == _DialogStep.connect ? _onConnect : _onPair,
            child: Text(_step == _DialogStep.connect
                ? t.devices_page.connect
                : t.devices_page.pair),
          ),
        ],
      ],
    );
  }

  bool _validate() {
    final ip = _ipCtrl.text.trim();
    final port = _portCtrl.text.trim();

    if (ip.isEmpty ||
        !RegExp(r'^[\d.]+$').hasMatch(ip) ||
        '.'.allMatches(ip).length < 2) {
      _showSnackbar(t.devices_page.invalid_ip);
      return false;
    }

    final portNum = int.tryParse(port);
    if (portNum == null || portNum < 1 || portNum > 65535) {
      _showSnackbar(t.devices_page.invalid_port);
      return false;
    }

    if (_step == _DialogStep.pair) {
      final code = _codeCtrl.text.trim();
      if (code.length != 6 || int.tryParse(code) == null) {
        _showSnackbar(t.devices_page.invalid_code);
        return false;
      }
    }

    return true;
  }

  Future<void> _onConnect() async {
    if (!_validate()) return;
    setState(() => _isLoading = true);
    try {
      final client = await ref.read(adbClientProvider.future);
      await client.connect(
        _ipCtrl.text.trim(),
        int.parse(_portCtrl.text.trim()),
      );
      if (!mounted) return;
      final serial = '${_ipCtrl.text.trim()}:${_portCtrl.text.trim()}';
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(t.devices_page.connected_to(serial: serial))),
      );
      ref.invalidate(adbDevicesWithInfoProvider);
    } on AdbException catch (e) {
      if (!mounted) return;
      if (e.message.contains('already connected')) {
        final serial =
            '${_ipCtrl.text.trim()}:${_portCtrl.text.trim()}';
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text(t.devices_page.connected_to(serial: serial))),
        );
        ref.invalidate(adbDevicesWithInfoProvider);
      } else {
        _showSnackbar(e.message);
        setState(() => _step = _DialogStep.pair);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _onPair() async {
    if (!_validate()) return;
    setState(() => _isLoading = true);
    try {
      final client = await ref.read(adbClientProvider.future);
      await client.pair(
        _ipCtrl.text.trim(),
        int.parse(_portCtrl.text.trim()),
        _codeCtrl.text.trim(),
      );
      await client.connect(
        _ipCtrl.text.trim(),
        int.parse(_portCtrl.text.trim()),
      );
      if (!mounted) return;
      final serial = '${_ipCtrl.text.trim()}:${_portCtrl.text.trim()}';
      Navigator.pop(context);
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(
            content: Text(
                t.devices_page.paired_and_connected(serial: serial))));
      ref.invalidate(adbDevicesWithInfoProvider);
    } on AdbException catch (e) {
      if (!mounted) return;
      _showSnackbar(_mapPairError(e.message));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _mapPairError(String raw) {
    if (raw.toLowerCase().contains('refused')) {
      return t.devices_page.connection_refused;
    }
    if (raw.contains('Invalid pairing code')) {
      return t.devices_page.invalid_pairing_code;
    }
    if (raw.contains('Pairing code must be 6 digits')) {
      return t.devices_page.invalid_code;
    }
    return raw;
  }

  void _showSnackbar(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}
