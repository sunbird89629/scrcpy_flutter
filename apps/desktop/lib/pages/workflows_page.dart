import 'package:autoglm_desktop/i18n/strings.g.dart';
import 'package:autoglm_ui_kit/autoglm_ui_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Page for managing automation workflows.
class WorkflowsPage extends ConsumerWidget {
  /// Creates a [WorkflowsPage].
  const WorkflowsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(t.nav.workflows),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () {},
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
      ),
      body: Center(
        child: Padding(
          padding: AppSpacing.edgeInsetsMd,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.playlist_add_check_outlined,
                size: 80,
                color: theme.colorScheme.primary.withOpacity(0.5),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'No Workflows Yet',
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: AppSpacing.sm),
              const Text(
                'Create your first automation workflow to get started.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.xl),
              FilledButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.add),
                label: const Text('Create Workflow'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
