import 'package:autoglm_core/autoglm_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Provider for the [SettingsRepository].
final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  throw UnimplementedError('Override this in the main.dart');
});

/// Provider for the application settings.
final settingsProvider = AsyncNotifierProvider<SettingsNotifier, Settings>(
  SettingsNotifier.new,
);

/// Notifier for managing application settings.
class SettingsNotifier extends AsyncNotifier<Settings> {
  @override
  Future<Settings> build() async {
    final repo = ref.watch(settingsRepositoryProvider);
    return repo.load();
  }

  /// Updates the application settings.
  Future<void> updateSettings(Settings settings) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final repo = ref.read(settingsRepositoryProvider);
      await repo.save(settings);
      return settings;
    });
  }
}
