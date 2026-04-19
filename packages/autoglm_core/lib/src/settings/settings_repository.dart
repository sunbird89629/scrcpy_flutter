import 'package:autoglm_core/src/settings/settings.dart';

/// Persists [Settings]. Implementations may use files, in-memory storage, etc.
abstract class SettingsRepository {
  /// Loads the persisted [Settings], returning defaults if none exist.
  Future<Settings> load();

  /// Saves the given [settings] to the backing store.
  Future<void> save(Settings settings);
}
