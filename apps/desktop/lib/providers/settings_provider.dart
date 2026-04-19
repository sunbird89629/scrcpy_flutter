import 'dart:async';
import 'dart:io';

import 'package:autoglm_core/autoglm_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Override in tests to inject a fake repository.
final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  throw UnimplementedError(
    'settingsRepositoryProvider must be overridden at app startup. '
    'Call ProviderScope(overrides: [...settingsRepositoryProvider...]).',
  );
});

/// Async-loaded current settings. Use `ref.watch(settingsProvider)` to react.
final settingsProvider =
    AsyncNotifierProvider<SettingsNotifier, Settings>(SettingsNotifier.new);

/// Notifier for managing persistent settings state via Riverpod.
///
/// Loads settings from the repository on startup and synchronises updates
/// with the backing storage.
class SettingsNotifier extends AsyncNotifier<Settings> {
  @override
  Future<Settings> build() async {
    final repo = ref.read(settingsRepositoryProvider);
    return repo.load();
  }

  /// Updates the current settings by applying a mutation function,
  /// then persists the changes to the repository.
  Future<void> updateSettings(Settings Function(Settings) mutate) async {
    final current = state.value ?? const Settings();
    final next = mutate(current);
    state = AsyncData(next);
    await ref.read(settingsRepositoryProvider).save(next);
  }
}

/// Helper used by `main()` to build the default file-backed repo.
Future<SettingsRepository> defaultSettingsRepository() async {
  final dir = await getApplicationSupportDirectory();
  final file = File(p.join(dir.path, 'settings.json'));
  return JsonFileSettingsRepository(file);
}

/// Helper used by `main()` to obtain the logs directory.
Future<Directory> defaultLogsDirectory() async {
  final dir = await getApplicationSupportDirectory();
  final logs = Directory(p.join(dir.path, 'logs'));
  if (!logs.existsSync()) {
    logs.createSync(recursive: true);
  }
  return logs;
}
