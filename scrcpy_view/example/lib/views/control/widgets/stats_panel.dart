import 'package:flutter/material.dart';
import 'package:scrcpy_view_example/stream_stats.dart';
import 'package:scrcpy_view_example/app_controller.dart';

class StatsPanel extends StatelessWidget {
  const StatsPanel({super.key, required this.stats});

  final StreamStats stats;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Stream Stats',
          style: TextStyle(color: Colors.white70, fontSize: 12),
        ),
        const SizedBox(height: 4),
        _statRow('Status', stats.status, _statusColor(stats.status)),
        _statRow(
            'Latency', '${stats.latencyMs}ms', _latencyColor(stats.latencyMs)),
        _statRow('FPS', '${stats.fps}', null),
        _statRow(
            'Buffered', '${stats.buffered}', _bufferedColor(stats.buffered)),
        const Divider(color: Colors.white24, height: 8),
        _statRow('Device', stats.deviceResolution, null),
        _statRow('Video Stream', stats.resolution, null),
        _statRow('Canvas CSS', stats.cssResolution, null),
      ],
    );
  }

  Widget _statRow(String label, String value, Color? color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(color: Colors.white54, fontSize: 11)),
          Text(
            value,
            style: TextStyle(
              color: color ?? Colors.greenAccent,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  Color _statusColor(String status) {
    if (status.startsWith('Error') || status == 'Disconnected') {
      return Colors.redAccent;
    }
    if (status == 'Connecting...') return Colors.orangeAccent;
    return Colors.greenAccent;
  }

  Color _latencyColor(int ms) {
    if (ms > 150) return Colors.redAccent;
    if (ms > 80) return Colors.orangeAccent;
    return Colors.greenAccent;
  }

  Color _bufferedColor(int n) {
    if (n > 5) return Colors.orangeAccent;
    return Colors.greenAccent;
  }
}
