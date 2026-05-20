import 'package:logging/logging.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

final _log = Logger('AppDatabase');

class AppDatabase {
  AppDatabase._();

  static Database? _database;

  static Future<Database> get database async {
    _database ??= await _open();
    return _database!;
  }

  static Future<Database> _open() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'murmur.db');
    _log.info('Opening database at $path');
    return openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  static Future<void> _onCreate(Database db, int version) async {
    _log.info('Creating database schema v$version');
    await db.execute('''
      CREATE TABLE reminders (
        id                 INTEGER PRIMARY KEY AUTOINCREMENT,
        task               TEXT    NOT NULL,
        time_str           TEXT,
        scheduled_at       INTEGER,
        speaker_id         TEXT    NOT NULL DEFAULT 'unknown',
        language           TEXT    NOT NULL DEFAULT 'en',
        confidence         REAL    NOT NULL DEFAULT 0.0,
        transcript_snippet TEXT,
        status             TEXT    NOT NULL DEFAULT 'pending',
        created_at         INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE INDEX idx_reminders_status
        ON reminders(status, created_at DESC)
    ''');
  }

  static Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    _log.info('Upgrading database from v$oldVersion to v$newVersion');
    // Future migrations go here keyed by version number.
  }
}
