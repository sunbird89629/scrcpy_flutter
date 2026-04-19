import 'package:autoglm_desktop/i18n/strings.g.dart';
import 'package:autoglm_desktop/providers/settings_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Side-effect provider: watches `Settings.locale` and pushes it into
/// slang's `LocaleSettings`. Watch it in the widget tree to apply.
///
/// `Settings.locale` is one of: 'system' | 'zh-CN' | 'en-US'.
final localeApplyProvider = Provider<void>((ref) {
  final asyncSettings = ref.watch(settingsProvider);
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
