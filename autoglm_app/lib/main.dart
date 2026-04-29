import 'dart:async';
import 'dart:io';

import 'package:autoglm_core/autoglm_core.dart';
import 'package:autoglm_app/app.dart';
import 'package:autoglm_app/i18n/strings.g.dart';
import 'package:autoglm_app/providers/settings_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_skill/flutter_skill.dart';
import 'package:mcp_toolkit/mcp_toolkit.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

void main() async {
  runZonedGuarded(
    () async {
      if (kDebugMode) FlutterSkillBinding.ensureInitialized();
      WidgetsFlutterBinding.ensureInitialized();
      MediaKit.ensureInitialized();

      // Initialize MCP Toolkit
      MCPToolkitBinding.instance
        ..initialize()
        ..initializeFlutterToolkit();

      // Initialize Core Services
      final appSupportDir = await getApplicationSupportDirectory();
      final logsDir = Directory(p.join(appSupportDir.path, 'logs'));
      if (!logsDir.existsSync()) {
        logsDir.createSync(recursive: true);
      }

      initAppLogger(logsDir: logsDir.path);
      appLogger.info('Starting AutoGLM Desktop...');

      // Global Error Handling
      FlutterError.onError = (details) {
        FlutterError.presentError(details);
        appLogger.e(
          'Flutter error: ${details.exception}',
          details.exception,
          details.stack,
        );
      };

      PlatformDispatcher.instance.onError = (error, stack) {
        appLogger.e('Platform error: $error', error, stack);
        return true;
      };

      final settingsPath = p.join(appSupportDir.path, 'settings.json');

      runApp(
        ProviderScope(
          observers: [_LoggerObserver()],
          overrides: [
            settingsRepositoryProvider.overrideWithValue(
              JsonFileSettingsRepository(filePath: settingsPath),
            ),
          ],
          child: TranslationProvider(child: const AutoGLMApp()),
        ),
      );
    },
    (error, stack) {
      // Critical: Handle zone errors for MCP server error reporting
      appLogger.e('Zone error: $error', error, stack);
      MCPToolkitBinding.instance.handleZoneError(error, stack);
    },
  );
}

class _LoggerObserver extends ProviderObserver {
  @override
  void didUpdateProvider(
    ProviderBase<Object?> provider,
    Object? previousValue,
    Object? newValue,
    ProviderContainer container,
  ) {
    if (newValue is AsyncValue && newValue.hasError) {
      appLogger.e(
        'Provider ${provider.name ?? provider.runtimeType} error: ${newValue.error}',
        newValue.error,
        newValue.stackTrace,
      );
    } else if (kDebugMode) {
      // Log provider transitions for debugging
      final name = provider.name ?? provider.runtimeType;
      appLogger.d('Provider $name update: $newValue');
    }
  }

  @override
  void providerDidFail(
    ProviderBase<Object?> provider,
    Object error,
    StackTrace stackTrace,
    ProviderContainer container,
  ) {
    appLogger.e(
      'Provider ${provider.name ?? provider.runtimeType} fatal failure: $error',
      error,
      stackTrace,
    );
  }

  @override
  void didAddProvider(
    ProviderBase<Object?> provider,
    Object? value,
    ProviderContainer container,
  ) {
    if (kDebugMode) {
      appLogger.d(
        'Provider ${provider.name ?? provider.runtimeType} added: $value',
      );
    }
  }
}
