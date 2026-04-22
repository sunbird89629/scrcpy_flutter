import 'dart:convert';
import 'dart:io';
import 'package:autoglm_core/src/logging/app_logger.dart';
import 'package:autoglm_core/src/settings.dart';

/// Repository for application settings.
abstract class SettingsRepository {
  /// Loads settings.
  Future<Settings> load();

  /// Saves settings.
  Future<void> save(Settings settings);
}

/// JSON file based implementation of [SettingsRepository].
class JsonFileSettingsRepository implements SettingsRepository {
  /// Creates new [JsonFileSettingsRepository].
  JsonFileSettingsRepository({required this.filePath});

  /// Path to the JSON file.
  final String filePath;

  @override
  Future<Settings> load() async {
    final file = File(filePath);
    if (!file.existsSync()) return const Settings();
    try {
      final content = await file.readAsString();
      return Settings.fromJson(jsonDecode(content) as Map<String, dynamic>);
    } on Object catch (e, st) {
      AppLogger.maybeError('Failed to load settings from $filePath', e, st);
      return const Settings();
    }
  }

  @override
  Future<void> save(Settings settings) async {
    final file = File(filePath);
    if (!file.parent.existsSync()) {
      await file.parent.create(recursive: true);
    }
    await file.writeAsString(jsonEncode(settings.toJson()));
  }
}
