import 'package:flutter/material.dart';
import 'package:scrcpy_view/scrcpy_view.dart';
import 'package:scrcpy_view_example/views/control/widgets/control_button.dart';
import 'package:scrcpy_view_example/views/control/widgets/stats_panel.dart';
import 'package:scrcpy_view_example/app_controller.dart';

class ControlView extends StatelessWidget {
  const ControlView({super.key});

  static const _navButtons = [
    (Icons.arrow_back, ScrcpyKeycode.back),
    (Icons.circle_outlined, ScrcpyKeycode.home),
    (Icons.menu, ScrcpyKeycode.appSwitch),
  ];

  @override
  Widget build(BuildContext context) {
    final controller = AppController();
    return ListenableBuilder(
      listenable: controller,
      builder: (context, child) {
        return SizedBox(
          width: 300,
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                color: Colors.indigo[800],
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ElevatedButton.icon(
                          key: const Key('start_button'),
                          onPressed:
                              controller.isRunning ? null : controller.start,
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('Start'),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton.icon(
                          key: const Key('stop_button'),
                          onPressed:
                              controller.isRunning ? controller.stop : null,
                          icon: const Icon(Icons.stop),
                          label: const Text('Stop'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red[900],
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    const Divider(color: Colors.white24, height: 24),
                    const Text(
                      'Remote Control',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: _navButtons
                          .map((b) => ControlButton(
                                icon: b.$1,
                                onPressed: () => controller.injectKey(b.$2),
                              ))
                          .toList(),
                    ),
                    const Divider(color: Colors.white24, height: 24),
                    StatsPanel(stats: controller.stats),
                  ],
                ),
              ),
              Expanded(
                child: Container(
                  width: double.infinity,
                  color: Colors.black,
                  padding: const EdgeInsets.all(8),
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
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
