import 'package:autoglm_app/i18n/strings.g.dart';
import 'package:autoglm_app/providers/settings_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Side-effect provider: watches `Settings.locale` and pushes it into
/// slang's `LocaleSettings`. Watch it in the widget tree to apply.
///
/// `Settings.locale` is one of: 'system' | 'zh-CN' | 'en-US'.
final localeApplyProvider = Provider<void>((ref) {
  final asyncSettings = ref.watch(settingsProvider);
  // ignore: cascade_invocations - side-effect operation, not a sequence
  asyncSettings.maybeWhen(
    data: (s) {
      if (s.locale == 'system') {
        LocaleSettings.useDeviceLocaleSync();
        return;
      }
      final match = AppLocaleUtils.parse(s.locale);
      LocaleSettings.setLocaleSync(match);
    },
    orElse: () {},
  );
});
