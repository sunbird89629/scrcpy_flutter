import 'package:autoglm_scrcpy_example/base_view.dart';
import 'package:autoglm_scrcpy_example/fpv/harness_controller.dart';
import 'package:flutter/material.dart';

class ControlView extends BaseView {
  const ControlView({super.key});

  @override
  Widget buildView(BuildContext context, HarnessController controller) {
    return SizedBox(
      width: 380,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.indigo[800],
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: controller.isRunning ? null : controller.start,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Start'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: controller.isRunning ? controller.stop : null,
                  icon: const Icon(Icons.stop),
                  label: const Text('Stop'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    foregroundColor: Colors.white,
                  ),
                ),
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
                itemBuilder: (context, i) => Text(
                  controller.logs[i],
                  style: const TextStyle(
                    color: Colors.greenAccent,
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
