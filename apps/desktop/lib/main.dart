import 'dart:io';

import 'package:autoglm_core/autoglm_core.dart';
import 'package:autoglm_desktop/app.dart';
import 'package:autoglm_desktop/i18n/strings.g.dart';
import 'package:autoglm_desktop/providers/settings_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  // Initialize Core Services
  final appSupportDir = await getApplicationSupportDirectory();
  final logsDir = Directory(p.join(appSupportDir.path, 'logs'));
  if (!logsDir.existsSync()) {
    logsDir.createSync(recursive: true);
  }

  initAppLogger(logsDir: logsDir.path);
  appLogger.info('Starting AutoGLM Desktop...');

  final settingsPath = p.join(appSupportDir.path, 'settings.json');

  runApp(
    ProviderScope(
      overrides: [
        settingsRepositoryProvider.overrideWithValue(
          JsonFileSettingsRepository(filePath: settingsPath),
        ),
      ],
      child: TranslationProvider(
        child: const AppShell(child: SizedBox.shrink()),
      ),
    ),
  );
}
