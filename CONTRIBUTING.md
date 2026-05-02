# Contributing to autoglm_scrcpy_flutter

Thank you for your interest in contributing! This guide will help you get started.

## Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) 3.24+ (check `.fvmrc` for the pinned version)
- [Melos](https://melos.invertase.dev/) (`dart pub global activate melos`)
- A physical Android device connected via USB (for scrcpy features)

## Getting Started

```bash
# Clone the repo
git clone https://github.com/sunbird89629/autoglm_scrcpy_flutter.git
cd autoglm_scrcpy_flutter

# Install dependencies and link local packages
melos bootstrap

# Run codegen (freezed, json_serializable, slang)
melos run gen
melos run gen:i18n
```

## Development

### Running the apps

```bash
cd autoglm_app && flutter run -d macos    # AI agent app
cd scrcpy_app && flutter run -d macos     # Scrcpy client app
```

### Common commands

```bash
melos run analyze       # Static analysis (fatal infos + warnings)
melos run format        # Check formatting
melos run format:fix    # Auto-fix formatting
melos run test          # Run all tests
```

### Code generation

After modifying freezed models, JSON serializable classes, or i18n strings:

```bash
melos run gen           # Regenerate freezed/json_serializable
melos run gen:i18n      # Regenerate slang i18n strings
```

## Project Structure

This is a Melos-managed monorepo. Lower layers must never import from upper layers.

```
packages/autoglm_logger ──> packages/autoglm_core
packages/autoglm_adb ────────────────┐
packages/autoglm_logger ─────────────┤
scrcpy_view (widget/protocol)  ──────┼──> scrcpy_app (scrcpy client)
                                      └──> scrcpy_mcp (MCP server)
```

| Package | Description |
|---------|-------------|
| `scrcpy_view` | Reusable Flutter widget + protocol library for Android screen mirroring |
| `scrcpy_app` | Standalone scrcpy desktop client |
| `scrcpy_mcp` | MCP server wrapping scrcpy operations |
| `autoglm_app` | AI agent desktop app |
| `packages/autoglm_core` | Shared settings, history, logging |
| `packages/autoglm_adb` | ADB binary wrapper |
| `packages/autoglm_logger` | Logging facade |

## Code Style

- Analysis rules: [very_good_analysis](https://pub.dev/packages/very_good_analysis) (configured in root `analysis_options.yaml`)
- Use `appLogger` from `package:autoglm_core` for all logging — never `print()`
- Follow existing patterns in the codebase; check neighboring files before introducing new ones

## Testing

```bash
# Run all tests
melos run test

# Run tests for a specific package
cd packages/autoglm_core && flutter test
```

- Tests requiring a physical Android device go in `*_real_device_test.dart`
- Use the `ScrcpyAdb` interface for testing without a real device
- Never add the `test` package as a dev_dependency — it conflicts with `flutter_test` from the SDK

## Submitting Changes

1. Fork the repository
2. Create a feature branch from `main`
3. Make your changes
4. Ensure `melos run analyze` and `melos run test` pass
5. Commit with clear, descriptive messages
6. Open a pull request

## Reporting Issues

Use [GitHub Issues](https://github.com/sunbird89629/autoglm_scrcpy_flutter/issues) to report bugs or request features. Include:

- Steps to reproduce
- Expected vs actual behavior
- Flutter version (`flutter --version`)
- macOS version
- Android device model and OS version (if applicable)

## License

By contributing, you agree that your contributions will be licensed under the [Apache License 2.0](LICENSE).
