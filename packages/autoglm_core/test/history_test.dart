import 'dart:io';
import 'package:autoglm_core/src/history/history_database.dart';
import 'package:autoglm_core/src/history/history_manager.dart';
import 'package:autoglm_core/src/models/history.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('HistoryManager', () {
    late Directory tempDir;
    late String dbPath;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('history_test');
      dbPath = p.join(tempDir.path, 'test_history.db');
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test('saves and lists conversations', () async {
      final db = HistoryDatabase(dbPath: dbPath);
      final manager = HistoryManager(database: db);

      final record = ConversationRecord(
        id: 'session-1',
        deviceId: 'device-1',
        startTime: DateTime.now(),
        lastUpdated: DateTime.now(),
        taskDescription: 'Do something',
      );

      await manager.addConversation(record);
      final list = await manager.listConversations();

      expect(list, hasLength(1));
      expect(list.first.id, 'session-1');
      expect(list.first.taskDescription, 'Do something');

      await manager.close();
    });
  });
}
