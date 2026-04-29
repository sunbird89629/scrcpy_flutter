import 'package:autoglm_core/autoglm_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Provider for the [HistoryDatabase].
final historyDatabaseProvider = Provider<Future<HistoryDatabase>>((ref) async {
  final appSupportDir = await getApplicationSupportDirectory();
  final dbPath = p.join(appSupportDir.path, 'history.db');
  return HistoryDatabase(dbPath: dbPath);
});

/// Provider for the [HistoryManager].
final historyManagerProvider = Provider<Future<HistoryManager>>((ref) async {
  final db = await ref.watch(historyDatabaseProvider);
  return HistoryManager(database: db);
});

/// Provider for the list of conversation records.
final historyConversationsProvider =
    FutureProvider.autoDispose<List<ConversationRecord>>((ref) async {
      final manager = await ref.watch(historyManagerProvider);
      return manager.listConversations();
    });
