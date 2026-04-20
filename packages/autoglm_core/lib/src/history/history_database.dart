import 'dart:io';
import 'package:autoglm_core/src/models/history.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class HistoryDatabase {
  HistoryDatabase({required this.dbPath});

  final String dbPath;
  Database? _db;

  Future<Database> get db async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    sqfliteFfiInit();
    final databaseFactory = databaseFactoryFfi;

    final dir = Directory(p.dirname(dbPath));
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }

    return databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE conversations (
              id TEXT PRIMARY KEY,
              device_id TEXT NOT NULL,
              start_time TEXT NOT NULL,
              last_updated TEXT NOT NULL,
              task_description TEXT,
              status TEXT NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE steps (
              id TEXT PRIMARY KEY,
              conversation_id TEXT NOT NULL,
              step_number INTEGER NOT NULL,
              timestamp TEXT NOT NULL,
              action TEXT NOT NULL,
              observation TEXT,
              screenshot_path TEXT,
              FOREIGN KEY (conversation_id) REFERENCES conversations (id) ON DELETE CASCADE
            )
          ''');
        },
      ),
    );
  }

  Future<void> insertConversation(ConversationRecord record) async {
    final d = await db;
    await d.insert('conversations', record.toJson(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<ConversationRecord>> listConversations(
      {int limit = 50, int offset = 0}) async {
    final d = await db;
    final maps = await d.query('conversations',
        orderBy: 'last_updated DESC', limit: limit, offset: offset);
    return maps.map((m) => ConversationRecord.fromJson(m)).toList();
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
