import 'package:autoglm_core/autoglm_core.dart';
import 'package:autoglm_app/i18n/strings.g.dart';
import 'package:autoglm_app/providers/settings_provider.dart';
import 'package:autoglm_ui_kit/autoglm_ui_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Page for application settings.
class SettingsPage extends ConsumerWidget {
  /// Creates a [SettingsPage].
  const SettingsPage({super.key});

  /// Key for the theme dropdown.
  static const themeDropdownKey = Key('theme-dropdown');

  /// Key for the locale dropdown.
  static const localeDropdownKey = Key('locale-dropdown');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(settingsProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(t.nav.settings)),
      body: settingsAsync.when(
        data: (settings) => ListView(
          padding: AppSpacing.edgeInsetsMd,
          children: [
            _buildSectionHeader(theme, 'Appearance'),
            Card(
              elevation: 0,
              color: theme.colorScheme.surfaceContainerLow,
              shape: RoundedRectangleBorder(borderRadius: AppRadius.borderMd),
              child: Column(
                children: [
                  _buildThemeSection(context, ref, settings),
                  const Divider(
                    indent: AppSpacing.md,
                    endIndent: AppSpacing.md,
                  ),
                  _buildLocaleSection(context, ref, settings),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            _buildSectionHeader(theme, 'LLM Configuration'),
            Card(
              elevation: 0,
              color: theme.colorScheme.surfaceContainerLow,
              shape: RoundedRectangleBorder(borderRadius: AppRadius.borderMd),
              child: Padding(
                padding: AppSpacing.edgeInsetsMd,
                child: _buildLlmSection(context, ref, settings),
              ),
            ),
          ],
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }

  Widget _buildSectionHeader(ThemeData theme, String title) {
    return Padding(
      padding: const EdgeInsets.only(
        left: AppSpacing.sm,
        bottom: AppSpacing.sm,
      ),
      child: Text(
        title.toUpperCase(),
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildThemeSection(
    BuildContext context,
    WidgetRef ref,
    Settings settings,
  ) {
    return ListTile(
      leading: const Icon(Icons.palette_outlined),
      title: Text(t.settings.theme.label),
      trailing: DropdownButton<String>(
        key: themeDropdownKey,
        underline: const SizedBox(),
        value: settings.themeMode,
        onChanged: (value) {
          if (value != null) {
            ref
                .read(settingsProvider.notifier)
                .updateSettings(settings.copyWith(themeMode: value));
          }
        },
        items: [
          DropdownMenuItem(
            value: 'system',
            child: Text(t.settings.theme.system),
          ),
          DropdownMenuItem(value: 'light', child: Text(t.settings.theme.light)),
          DropdownMenuItem(value: 'dark', child: Text(t.settings.theme.dark)),
        ],
      ),
    );
  }

  Widget _buildLocaleSection(
    BuildContext context,
    WidgetRef ref,
    Settings settings,
  ) {
    return ListTile(
      leading: const Icon(Icons.language_outlined),
      title: Text(t.settings.locale.label),
      trailing: DropdownButton<String>(
        key: localeDropdownKey,
        underline: const SizedBox(),
        value: settings.locale,
        onChanged: (value) {
          if (value != null) {
            ref
                .read(settingsProvider.notifier)
                .updateSettings(settings.copyWith(locale: value));
          }
        },
        items: [
          DropdownMenuItem(
            value: 'system',
            child: Text(t.settings.locale.system),
          ),
          const DropdownMenuItem(value: 'zh-CN', child: Text('简体中文')),
          const DropdownMenuItem(value: 'en-US', child: Text('English')),
        ],
      ),
    );
  }

  Widget _buildLlmSection(
    BuildContext context,
    WidgetRef ref,
    Settings settings,
  ) {
    return TextField(
      decoration: const InputDecoration(
        labelText: 'API Key',
        border: OutlineInputBorder(),
        prefixIcon: Icon(Icons.key),
      ),
      obscureText: true,
      controller: TextEditingController(text: settings.llmApiKey),
      onSubmitted: (value) {
        ref
            .read(settingsProvider.notifier)
            .updateSettings(settings.copyWith(llmApiKey: value));
      },
    );
  }
}
