import 'package:autoglm_scrcpy_example/fpv/fpv_controller.dart';
import 'package:flutter/material.dart';

class FpvScope extends InheritedNotifier<FpvController> {
  const FpvScope({
    super.key,
    required FpvController controller,
    required super.child,
  }) : super(notifier: controller);

  static FpvController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<FpvScope>();
    assert(scope != null, 'FpvScope.of() called without an ancestor');
    return scope!.notifier!;
  }
}
