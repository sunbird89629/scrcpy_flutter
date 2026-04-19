import 'package:autoglm_desktop/i18n/strings.g.dart';
import 'package:flutter/material.dart';

/// Chat landing page.
class ChatPage extends StatelessWidget {
  /// Creates a [ChatPage].
  const ChatPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(t.nav.chat)),
      body: Center(child: Text(t.page.chat.placeholder)),
    );
  }
}
