/// Application settings.
class Settings {
  /// Creates new [Settings].
  const Settings({
    this.themeMode = 'system',
    this.locale = 'system',
    this.llmProvider = 'gemini',
    this.llmBaseUrl = '',
    this.llmModel = 'gemini-1.5-pro',
    this.llmApiKey = '',
    this.mcpServerEnabled = false,
    this.mcpServerPort = 3000,
  });

  /// Creates settings from a JSON map.
  factory Settings.fromJson(Map<String, dynamic> json) => Settings(
        themeMode: json['themeMode'] as String? ?? 'system',
        locale: json['locale'] as String? ?? 'system',
        llmProvider: json['llmProvider'] as String? ?? 'gemini',
        llmBaseUrl: json['llmBaseUrl'] as String? ?? '',
        llmModel: json['llmModel'] as String? ?? 'gemini-1.5-pro',
        llmApiKey: json['llmApiKey'] as String? ?? '',
        mcpServerEnabled: json['mcpServerEnabled'] as bool? ?? false,
        mcpServerPort: json['mcpServerPort'] as int? ?? 3000,
      );

  /// Current theme mode.
  final String themeMode;

  /// Current locale.
  final String locale;

  /// Selected LLM provider.
  final String llmProvider;

  /// Base URL for the LLM provider.
  final String llmBaseUrl;

  /// Model name for the LLM provider.
  final String llmModel;

  /// API key for the LLM provider.
  final String llmApiKey;

  /// Whether the MCP server is enabled.
  final bool mcpServerEnabled;

  /// Port for the MCP server.
  final int mcpServerPort;

  /// Creates a copy of this settings with the given fields replaced.
  Settings copyWith({
    String? themeMode,
    String? locale,
    String? llmProvider,
    String? llmBaseUrl,
    String? llmModel,
    String? llmApiKey,
    bool? mcpServerEnabled,
    int? mcpServerPort,
  }) =>
      Settings(
        themeMode: themeMode ?? this.themeMode,
        locale: locale ?? this.locale,
        llmProvider: llmProvider ?? this.llmProvider,
        llmBaseUrl: llmBaseUrl ?? this.llmBaseUrl,
        llmModel: llmModel ?? this.llmModel,
        llmApiKey: llmApiKey ?? this.llmApiKey,
        mcpServerEnabled: mcpServerEnabled ?? this.mcpServerEnabled,
        mcpServerPort: mcpServerPort ?? this.mcpServerPort,
      );

  /// Converts settings to a JSON map.
  Map<String, dynamic> toJson() => {
        'themeMode': themeMode,
        'locale': locale,
        'llmProvider': llmProvider,
        'llmBaseUrl': llmBaseUrl,
        'llmModel': llmModel,
        'llmApiKey': llmApiKey,
        'mcpServerEnabled': mcpServerEnabled,
        'mcpServerPort': mcpServerPort,
      };
}
