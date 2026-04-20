import 'package:autoglm_desktop/i18n/strings.g.dart';
import 'package:autoglm_desktop/providers/history_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Page for viewing conversation history.
class HistoryPage extends ConsumerWidget {
  /// Creates a [HistoryPage].
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conversationsAsync = ref.watch(historyConversationsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(t.nav.history),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(historyConversationsProvider),
          ),
        ],
      ),
      body: conversationsAsync.when(
        data: (list) {
          if (list.isEmpty) {
            return const Center(child: Text('No history found.'));
          }
          return ListView.builder(
            itemCount: list.length,
            itemBuilder: (context, index) {
              final record = list[index];
              return ListTile(
                leading: const Icon(Icons.history),
                title: Text(record.taskDescription ?? 'No description'),
                subtitle: Text(
                  'Device: ${record.deviceId} • '
                  '${record.startTime.toLocal().toString().split('.').first}',
                ),
                trailing: Chip(
                  label: Text(record.status),
                  visualDensity: VisualDensity.compact,
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
}
