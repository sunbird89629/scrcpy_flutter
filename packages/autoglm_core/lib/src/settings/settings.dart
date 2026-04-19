import 'package:flutter/material.dart' show ThemeMode;
import 'package:freezed_annotation/freezed_annotation.dart';

part 'settings.freezed.dart';
part 'settings.g.dart';

/// Persistent user-facing settings for AutoGLM.
@freezed
class Settings with _$Settings {
  /// Creates a [Settings] instance with optional field overrides.
  ///
  /// All fields default to sensible out-of-the-box values so callers can
  /// omit any field they do not need to customise.
  const factory Settings({
    @Default(ThemeMode.system) ThemeMode themeMode,
    @Default('system') String locale,
    @Default('https://open.bigmodel.cn/api/paas/v4') String llmBaseUrl,
    @Default('autoglm-phone') String llmModel,
    @Default('') String llmApiKey,
    @Default(false) bool mcpServerEnabled,
    @Default(8765) int mcpServerPort,
  }) = _Settings;

  /// Deserialises [Settings] from a JSON map.
  ///
  /// Missing keys fall back to their default values, making it safe to call
  /// with a partial or empty map.
  factory Settings.fromJson(Map<String, dynamic> json) =>
      _$SettingsFromJson(json);
}
