import 'package:flutter/material.dart';
import 'package:scrcpy_app/app_controller.dart';
import 'package:scrcpy_app/mcp_server_panel.dart';
import 'package:scrcpy_app/views/floating_control_button.dart';

class ControlView extends StatelessWidget {
  const ControlView({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final AppController appController = AppController();
    return AspectRatio(
      aspectRatio: 0.6,
      child: ListenableBuilder(
        listenable: appController.mcpServerController,
        builder: (_, __) {
          return Scaffold(
            floatingActionButtonLocation:
                FloatingActionButtonLocation.centerFloat,
            floatingActionButton: FloatingControlButton(),
            body: Column(
              children: [
                Expanded(
                  child: McpServerPanel(
                    controller: appController.mcpServerController,
                  ),
                ),
                // ControlButtonWidget(),
              ],
            ),
          );
        },
      ),
    );
  }
}
