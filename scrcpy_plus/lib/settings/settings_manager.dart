import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:scrcpy_plus/scrcpy/scrcpy_config.dart';

/// Persists app settings and known device serials to JSON files.
class SettingsManager {
  SettingsManager({required this.configDir});

  final String configDir;

  String get _configPath => p.join(configDir, 'settings.json');
  String get _knownSerialsPath => p.join(configDir, 'known_devices.json');

  Future<ScrcpyConfig> loadConfig() async {
    final file = File(_configPath);
    if (!file.existsSync()) return const ScrcpyConfig();
    final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    return ScrcpyConfig.fromJson(json);
  }

  Future<void> saveConfig(ScrcpyConfig config) async {
    final file = File(_configPath);
    await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(config.toJson()),
    );
  }

  Future<List<String>> loadKnownSerials() async {
    final file = File(_knownSerialsPath);
    if (!file.existsSync()) return [];
    final json = jsonDecode(await file.readAsString()) as List;
    return json.cast<String>();
  }

  Future<void> saveKnownSerials(List<String> serials) async {
    final file = File(_knownSerialsPath);
    await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(serials),
    );
  }
}
