import 'package:autoglm_scrcpy_example/harness_controller.dart';
import 'package:flutter/material.dart';

/// Inherited scope exposing a [HarnessController] to descendants. Any
/// widget that calls [HarnessScope.of] in its `build` rebuilds when the
/// controller calls `notifyListeners()`.
class HarnessScope extends InheritedNotifier<HarnessController> {
  const HarnessScope({
    super.key,
    required HarnessController controller,
    required super.child,
  }) : super(notifier: controller);

  static HarnessController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<HarnessScope>();
    assert(scope != null, 'HarnessScope.of() called without an ancestor');
    return scope!.notifier!;
  }
}
