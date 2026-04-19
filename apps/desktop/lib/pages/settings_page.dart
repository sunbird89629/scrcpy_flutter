import 'package:autoglm_core/autoglm_core.dart';
import 'package:autoglm_desktop/i18n/strings.g.dart';
import 'package:autoglm_desktop/providers/settings_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Settings page: theme, locale, LLM config, MCP server.
class SettingsPage extends ConsumerWidget {
  /// Creates a [SettingsPage].
  const SettingsPage({super.key});

  /// Key for the theme dropdown.
  static const themeDropdownKey = ValueKey('settings.theme-dropdown');

  /// Key for the locale dropdown.
  static const localeDropdownKey = ValueKey('settings.locale-dropdown');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncSettings = ref.watch(settingsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(t.nav.settings)),
      body: asyncSettings.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Error: $e')),
        data: (s) => ListView(
          padding: const EdgeInsets.all(24),
          children: [
            _ThemeRow(settings: s),
            const SizedBox(height: 16),
            _LocaleRow(settings: s),
            const SizedBox(height: 16),
            _LlmRow(settings: s),
            const SizedBox(height: 16),
            _McpRow(settings: s),
          ],
        ),
      ),
    );
  }
}

/// Theme selection row.
class _ThemeRow extends ConsumerWidget {
  /// Creates a [_ThemeRow].
  const _ThemeRow({required this.settings});

  /// The current settings.
  final Settings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      children: [
        SizedBox(width: 120, child: Text(t.settings.theme.label)),
        DropdownButton<ThemeMode>(
          key: SettingsPage.themeDropdownKey,
          value: settings.themeMode,
          items: [
            DropdownMenuItem(
              value: ThemeMode.system,
              child: Text(t.settings.theme.system),
            ),
            DropdownMenuItem(
              value: ThemeMode.light,
              child: Text(t.settings.theme.light),
            ),
            DropdownMenuItem(
              value: ThemeMode.dark,
              child: Text(t.settings.theme.dark),
            ),
          ],
          onChanged: (v) {
            if (v == null) return;
            ref
                .read(settingsProvider.notifier)
                .updateSettings((s) => s.copyWith(themeMode: v));
          },
        ),
      ],
    );
  }
}

/// Locale selection row.
class _LocaleRow extends ConsumerWidget {
  /// Creates a [_LocaleRow].
  const _LocaleRow({required this.settings});

  /// The current settings.
  final Settings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      children: [
        SizedBox(width: 120, child: Text(t.settings.locale.label)),
        DropdownButton<String>(
          key: SettingsPage.localeDropdownKey,
          value: settings.locale,
          items: [
            DropdownMenuItem(
              value: 'system',
              child: Text(t.settings.locale.system),
            ),
            const DropdownMenuItem(value: 'zh-CN', child: Text('zh-CN')),
            const DropdownMenuItem(value: 'en-US', child: Text('en-US')),
          ],
          onChanged: (v) {
            if (v == null) return;
            ref
                .read(settingsProvider.notifier)
                .updateSettings((s) => s.copyWith(locale: v));
          },
        ),
      ],
    );
  }
}

/// LLM configuration row.
class _LlmRow extends ConsumerWidget {
  /// Creates a [_LlmRow].
  const _LlmRow({required this.settings});

  /// The current settings.
  final Settings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('LLM'),
        const SizedBox(height: 8),
        TextFormField(
          initialValue: settings.llmBaseUrl,
          decoration: const InputDecoration(labelText: 'Base URL'),
          onChanged: (v) => ref
              .read(settingsProvider.notifier)
              .updateSettings((s) => s.copyWith(llmBaseUrl: v)),
        ),
        TextFormField(
          initialValue: settings.llmModel,
          decoration: const InputDecoration(labelText: 'Model'),
          onChanged: (v) => ref
              .read(settingsProvider.notifier)
              .updateSettings((s) => s.copyWith(llmModel: v)),
        ),
        TextFormField(
          initialValue: settings.llmApiKey,
          decoration: const InputDecoration(labelText: 'API Key'),
          obscureText: true,
          onChanged: (v) => ref
              .read(settingsProvider.notifier)
              .updateSettings((s) => s.copyWith(llmApiKey: v)),
        ),
      ],
    );
  }
}

/// MCP server configuration row.
class _McpRow extends ConsumerWidget {
  /// Creates a [_McpRow].
  const _McpRow({required this.settings});

  /// The current settings.
  final Settings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('MCP Server'),
        SwitchListTile(
          title: const Text('Enabled'),
          value: settings.mcpServerEnabled,
          onChanged: (v) => ref
              .read(settingsProvider.notifier)
              .updateSettings((s) => s.copyWith(mcpServerEnabled: v)),
        ),
        TextFormField(
          initialValue: settings.mcpServerPort.toString(),
          decoration: const InputDecoration(labelText: 'Port'),
          keyboardType: TextInputType.number,
          onChanged: (v) {
            final port = int.tryParse(v);
            if (port == null) return;
            ref
                .read(settingsProvider.notifier)
                .updateSettings((s) => s.copyWith(mcpServerPort: port));
          },
        ),
      ],
    );
  }
}
