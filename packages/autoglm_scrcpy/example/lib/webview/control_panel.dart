import 'package:autoglm_scrcpy/autoglm_scrcpy.dart';
import 'package:autoglm_scrcpy_example/webview/webview_scope.dart';
import 'package:flutter/material.dart';

class ControlPanel extends StatelessWidget {
  const ControlPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = WebViewScope.of(context);
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
                if (controller.isRunning) ...[
                  const Divider(color: Colors.white24, height: 24),
                  const Text(
                    'Remote Control',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _controlBtn(Icons.arrow_back,
                          () => controller.injectKey(ScrcpyKeycode.back)),
                      _controlBtn(Icons.circle_outlined,
                          () => controller.injectKey(ScrcpyKeycode.home)),
                      _controlBtn(Icons.menu,
                          () => controller.injectKey(ScrcpyKeycode.appSwitch)),
                    ],
                  ),
                ],
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
  }

  Widget _controlBtn(IconData icon, VoidCallback onPressed) {
    return IconButton(
      icon: Icon(icon, color: Colors.white),
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: Colors.white10,
        padding: const EdgeInsets.all(12),
      ),
    );
  }
}
