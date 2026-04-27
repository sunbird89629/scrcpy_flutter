import 'package:autoglm_scrcpy_example/fpv/harness_controller.dart';
import 'package:autoglm_scrcpy_example/fpv/harness_scope.dart';
import 'package:flutter/material.dart';

abstract class BaseView extends StatelessWidget {
  const BaseView({super.key});

  @override
  Widget build(BuildContext context) {
    return buildView(context, HarnessScope.of(context));
  }

  Widget buildView(BuildContext context, HarnessController scope);
}
