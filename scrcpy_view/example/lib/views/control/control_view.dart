import 'package:flutter/material.dart';
import 'package:scrcpy_view/scrcpy_view.dart';
import 'package:scrcpy_view_example/app_controller.dart';
import 'package:scrcpy_view_example/views/control/widgets/control_button.dart';
import 'package:scrcpy_view_example/views/control/widgets/stats_panel.dart';

class ControlView extends StatelessWidget {
  const ControlView({
    super.key,
    this.width = 300,
  });
  final double width;

  @override
  Widget build(BuildContext context) {
    final controller = AppController();
    return ListenableBuilder(
      listenable: controller,
      builder: (context, child) {
        return Container(
          width: this.width,
          padding: EdgeInsets.all(12),
          color: Colors.blueGrey[900],
          child: Column(
            children: [
              _buildSwitchWidget(controller),
              Divider(height: 40),
              _buildControlWidget(controller),
              Divider(height: 40),
              StatsPanel(stats: controller.stats),
              Divider(height: 40),
              _buildLogWidget(controller),
            ],
          ),
        );
      },
    );
  }

  Expanded _buildLogWidget(AppController controller) {
    return Expanded(
      child: ListView.builder(
        itemCount: controller.logs.length,
        itemBuilder: (context, index) => Text(
          controller.logs[index],
          style: const TextStyle(
            color: Colors.blueAccent,
            fontSize: 10,
            fontFamily: 'monospace',
          ),
        ),
      ),
    );
  }

  Row _buildControlWidget(AppController controller) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: defaultNavButtons
          .map((b) => ControlButton(
                icon: b.$1,
                onPressed: () => controller.injectKey(b.$2),
              ))
          .toList(),
    );
  }

  Row _buildSwitchWidget(AppController controller) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ElevatedButton.icon(
          key: const Key('start_button'),
          onPressed: controller.showViewer ? null : controller.start,
          icon: const Icon(Icons.play_arrow),
          label: const Text('Start'),
        ),
        const SizedBox(width: 12),
        ElevatedButton.icon(
          key: const Key('stop_button'),
          onPressed: controller.showViewer ? controller.stop : null,
          icon: const Icon(Icons.stop),
          label: const Text('Stop'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red[900],
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }
}
