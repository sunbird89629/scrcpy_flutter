import 'package:flutter/widgets.dart';

void main() {
  // No window — pure menu-bar app
  runApp(const _Placeholder());
}

class _Placeholder extends StatelessWidget {
  const _Placeholder();

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}
