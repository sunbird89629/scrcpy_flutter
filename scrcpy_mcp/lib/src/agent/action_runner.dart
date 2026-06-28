import 'response_parser.dart';

/// Coordinate space autoglm-phone emits: every `element`/`start`/`end` value is
/// normalized to `[0, 1000]` on both axes (see the official handler:
/// `x = element[0] / 1000 * screen_width`). Transport primitives receive these
/// raw normalized values; each runner maps them to its own device space.
const kModelCoordSpace = 1000;

/// Common app name → package mappings for autoglm-phone's `Launch` action.
const _appNameToPackage = {
  'Chrome': 'com.android.chrome',
  'chrome': 'com.android.chrome',
  'YouTube': 'com.google.android.youtube',
  'youtube': 'com.google.android.youtube',
  '微信': 'com.tencent.mm',
  'WeChat': 'com.tencent.mm',
  '支付宝': 'com.eg.android.AlipayGphone',
  '美团': 'com.sankuai.meituan',
  '大众点评': 'com.dianping.v1',
  '抖音': 'com.ss.android.ugc.aweme',
  '小红书': 'com.xingin.xhs',
  '百度': 'com.baidu.searchbox',
  '高德地图': 'com.autonavi.minimap',
  '淘宝': 'com.taobao.taobao',
  '京东': 'com.jingdong.app.mall',
  '拼多多': 'com.xunmeng.pinduoduo',
};

/// Translates a [PhoneAction] into device operations.
///
/// This base owns the parts that are identical across transports — action
/// dispatch, the app-name table, argument validation, and the composite
/// `Double Tap`/`Wait` actions. It is transport-agnostic: it holds no `adb` or
/// session handle. Concrete subclasses implement only the transport primitives
/// ([tapAt], [swipeFromTo], [clearAndType], [pressBack], [pressHome],
/// [longPressAt], [launchPackage]); the coordinate primitives receive values in
/// the [kModelCoordSpace] normalized grid.
///
/// [run] matches the `PhoneAgent` `ActionRunner` typedef, so an instance can be
/// passed straight through as `actionRunner: runner.run`.
abstract class PhoneActionRunner {
  const PhoneActionRunner();

  /// Executes [action] and returns a short human-readable result that the agent
  /// feeds back to the model.
  Future<String> run(PhoneAction action) {
    switch (action) {
      case final DoAction d:
        return _runDo(d);
      case final FinishAction f:
        return Future.value(f.message);
    }
  }

  Future<String> _runDo(DoAction a) async {
    switch (a.action) {
      case 'Tap':
        final c = _coords(a.element);
        if (c == null) return 'Error: Tap missing coordinates';
        await tapAt(c.$1, c.$2);
        return 'Tapped at (${c.$1}, ${c.$2})';

      case 'Swipe':
        if (a.start == null ||
            a.end == null ||
            a.start!.length < 2 ||
            a.end!.length < 2) {
          return 'Error: Swipe missing start/end coordinates';
        }
        await swipeFromTo(a.start![0], a.start![1], a.end![0], a.end![1]);
        return 'Swiped from (${a.start![0]}, ${a.start![1]}) '
            'to (${a.end![0]}, ${a.end![1]})';

      case 'Type':
      case 'Type_Name':
        if (a.text == null) return 'Error: Type missing text';
        await clearAndType(a.text!);
        return 'Typed: ${a.text}';

      case 'Launch':
        return _launch(a);

      case 'Back':
        await pressBack();
        return 'Pressed Back';

      case 'Home':
        await pressHome();
        return 'Pressed Home';

      case 'Long Press':
        final c = _coords(a.element);
        if (c == null) return 'Error: Long Press missing coordinates';
        await longPressAt(c.$1, c.$2);
        return 'Long pressed at (${c.$1}, ${c.$2})';

      case 'Double Tap':
        final c = _coords(a.element);
        if (c == null) return 'Error: Double Tap missing coordinates';
        await tapAt(c.$1, c.$2);
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await tapAt(c.$1, c.$2);
        return 'Double tapped at (${c.$1}, ${c.$2})';

      case 'Wait':
        final secs =
            int.tryParse(
              (a.duration ?? '2s').replaceAll(RegExp('[^0-9]'), ''),
            ) ??
            2;
        await Future<void>.delayed(Duration(seconds: secs));
        return 'Waited ${secs}s';

      case 'Note':
        // Recording-only action: nothing to do on-device, just acknowledge so
        // the agent loop continues.
        return 'Noted';

      case 'Call_API':
        // Summarize/comment action with no on-device effect in this headless
        // flow; acknowledge with the model's instruction so the loop continues.
        return 'Acknowledged: ${a.message ?? 'summary'}';

      case 'Take_over':
        // PhoneAgent normally intercepts Take_over before reaching the runner;
        // handled here too for direct callers.
        return 'Manual intervention requested: ${a.message ?? 'no details'}';

      default:
        return 'Unknown action: ${a.action}';
    }
  }

  Future<String> _launch(DoAction a) async {
    if (a.app == null) return 'Error: Launch missing app name';
    final pkg = _appNameToPackage[a.app] ?? a.app!;
    final ok = await launchPackage(pkg);
    return ok ? 'Launched ${a.app} ($pkg)' : 'Failed to launch $pkg';
  }

  /// `[x, y]` from a coordinate field, or null if absent/malformed.
  (int, int)? _coords(List<int>? e) =>
      (e == null || e.length < 2) ? null : (e[0], e[1]);

  // ── Transport primitives (coordinates in the kModelCoordSpace grid) ──────────

  Future<void> tapAt(int x, int y);
  Future<void> swipeFromTo(int x1, int y1, int x2, int y2);

  /// Clears the focused field, then types [text]. autoglm-phone's `Type`
  /// *replaces* a field's content, so the field must be cleared first.
  Future<void> clearAndType(String text);

  Future<void> pressBack();
  Future<void> pressHome();
  Future<void> longPressAt(int x, int y);

  /// Launches the app with package id [pkg]. Returns whether it succeeded.
  Future<bool> launchPackage(String pkg);
}
