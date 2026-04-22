import 'dart:convert';
import 'dart:io';

import 'package:autoglm_core/src/logging/app_logger.dart';
import 'package:autoglm_core/src/settings/settings.dart';
import 'package:autoglm_core/src/settings/settings_repository.dart';

/// Stores [Settings] as a single JSON file.
///
/// On corrupted JSON, returns defaults rather than throwing — settings should
/// never block app startup.
class JsonFileSettingsRepository implements SettingsRepository {
  /// Creates a [JsonFileSettingsRepository] backed by [_file].
  JsonFileSettingsRepository(this._file);

  final File _file;

  @override
  Future<Settings> load() async {
    if (!_file.existsSync()) {
      return const Settings();
    }
    try {
      final raw = await _file.readAsString();
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return Settings.fromJson(json);
    } on Object catch (e, st) {
      AppLogger.maybeError('Failed to load settings from ${_file.path}', e, st);
      return const Settings();
    }
  }

  @override
  Future<void> save(Settings settings) async {
    final dir = _file.parent;
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    final encoded = const JsonEncoder.withIndent('  ').convert(
      settings.toJson(),
    );
    await _file.writeAsString(encoded);
  }
}
