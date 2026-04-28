import 'package:autoglm_app/i18n/strings.g.dart';
import 'package:autoglm_app/providers/history_provider.dart';
import 'package:autoglm_ui_kit/autoglm_ui_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Page for viewing conversation history.
class HistoryPage extends ConsumerWidget {
  /// Creates a [HistoryPage].
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conversationsAsync = ref.watch(historyConversationsProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(t.nav.history),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(historyConversationsProvider),
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
      ),
      body: conversationsAsync.when(
        data: (list) {
          if (list.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.history_outlined,
                      size: 64, color: theme.colorScheme.outline),
                  const SizedBox(height: AppSpacing.md),
                  const Text('No history found.'),
                ],
              ),
            );
          }
          return ListView.separated(
            padding: AppSpacing.edgeInsetsMd,
            itemCount: list.length,
            separatorBuilder: (context, index) =>
                const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, index) {
              final record = list[index];
              return Card(
                elevation: 0,
                color: theme.colorScheme.surfaceContainerLow,
                shape: RoundedRectangleBorder(
                  borderRadius: AppRadius.borderMd,
                  side: BorderSide(color: theme.colorScheme.outlineVariant),
                ),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: theme.colorScheme.primaryContainer,
                    child: Icon(Icons.history, color: theme.colorScheme.primary),
                  ),
                  title: Text(
                    record.taskDescription ?? 'No description',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    'Device: ${record.deviceId} • '
                    '${record.startTime.toLocal().toString().split('.').first}',
                  ),
                  trailing: _buildStatusChip(theme, record.status),
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }

  Widget _buildStatusChip(ThemeData theme, String status) {
    Color color;
    switch (status.toLowerCase()) {
      case 'success':
        color = Colors.green;
        break;
      case 'failed':
        color = theme.colorScheme.error;
        break;
      default:
        color = theme.colorScheme.secondary;
    }

    return Chip(
      label: Text(
        status,
        style: TextStyle(color: color, fontSize: 12),
      ),
      backgroundColor: color.withOpacity(0.1),
      side: BorderSide(color: color.withOpacity(0.2)),
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
    );
  }
}
