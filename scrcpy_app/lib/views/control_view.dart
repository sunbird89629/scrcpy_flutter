import 'package:flutter/material.dart';
import 'package:scrcpy_app/app_controller.dart';
import 'package:scrcpy_app/mcp_server_panel.dart';
import 'package:scrcpy_app/theme/app_theme.dart';
import 'package:scrcpy_app/views/control_button_widget.dart';

class ControlView extends StatelessWidget {
  const ControlView({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final AppController appController = AppController();
    final sidebarColor =
        Theme.of(context).extension<AppColors>()?.sidebarBackground;

    return Expanded(
      child: Container(
        color: sidebarColor,
        child: ListenableBuilder(
          listenable: appController.mcpServerController,
          builder: (_, __) {
            return Column(
              children: [
                Expanded(
                  child: McpServerPanel(
                    controller: appController.mcpServerController,
                  ),
                ),
                ControlButtonWidget(),
              ],
            );
          },
        ),
      ),
    );
  }
}
