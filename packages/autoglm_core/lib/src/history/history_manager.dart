import 'package:autoglm_core/src/history/history_database.dart';
import 'package:autoglm_core/src/models/history.dart';

/// Manages conversation history records and persistence.
class HistoryManager {
  /// Creates a new [HistoryManager].
  HistoryManager({required this.database});

  /// Database used for history persistence.
  final HistoryDatabase database;

  /// Adds a new conversation record.
  Future<void> addConversation(ConversationRecord record) async {
    await database.insertConversation(record);
  }

  /// Returns a list of conversation records.
  Future<List<ConversationRecord>> listConversations({
    int limit = 50,
    int offset = 0,
  }) async {
    return database.listConversations(limit: limit, offset: offset);
  }

  /// Closes the history manager and underlying database.
  Future<void> close() async {
    await database.close();
  }
}
