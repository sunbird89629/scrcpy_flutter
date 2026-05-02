import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'mcp_server_controller.dart';

class McpServerPanel extends StatefulWidget {
  const McpServerPanel({super.key, required this.controller});

  final McpServerController controller;

  @override
  State<McpServerPanel> createState() => _McpServerPanelState();
}

class _McpServerPanelState extends State<McpServerPanel> {
  late final TextEditingController _portCtrl;

  @override
  void initState() {
    super.initState();
    _portCtrl = TextEditingController(text: widget.controller.port.toString());
  }

  @override
  void dispose() {
    _portCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.controller;
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child:
          ctrl.isRunning ? _buildRunning(ctrl, theme) : _buildIdle(ctrl, theme),
    );
  }

  Widget _buildIdle(McpServerController ctrl, ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('MCP Server'),
            const SizedBox(width: 12),
            const Text('Port:'),
            const SizedBox(width: 8),
            SizedBox(
              width: 72,
              child: TextField(
                controller: _portCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  isDense: true,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) {
                  final parsed = int.tryParse(v);
                  if (parsed != null) ctrl.port = parsed;
                },
              ),
            ),
            const SizedBox(width: 12),
            FilledButton(
              onPressed: ctrl.start,
              child: const Text('Start'),
            ),
          ],
        ),
        if (ctrl.errorMessage != null) ...[
          const SizedBox(height: 4),
          Text(
            ctrl.errorMessage!,
            style: TextStyle(
              color: theme.colorScheme.error,
              fontSize: 12,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildRunning(McpServerController ctrl, ThemeData theme) {
    final url = ctrl.serverUrl ?? '';
    return Row(
      children: [
        Icon(Icons.circle, color: theme.colorScheme.primary, size: 10),
        const SizedBox(width: 8),
        const Text('MCP Running'),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            url,
            style: theme.textTheme.bodySmall,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        IconButton(
          icon: const Icon(Icons.copy, size: 18),
          tooltip: 'Copy URL',
          onPressed: () => Clipboard.setData(ClipboardData(text: url)),
        ),
        const SizedBox(width: 4),
        OutlinedButton(
          onPressed: ctrl.stop,
          child: const Text('Stop'),
        ),
      ],
    );
  }
}
