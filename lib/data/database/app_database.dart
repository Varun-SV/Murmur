import 'package:logging/logging.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

final _log = Logger('AppDatabase');

const int _dbVersion = 2;

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
      version: _dbVersion,
      onConfigure: _onConfigure,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onOpen: _onOpen,
    );
  }

  static Future<void> _onConfigure(Database db) async {
    await db.execute('PRAGMA journal_mode=WAL;');
    await db.execute('PRAGMA foreign_keys=ON;');
    await db.execute('PRAGMA synchronous=NORMAL;');
    await db.execute('PRAGMA cache_size=-8000;');
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
    await db.execute('''
      CREATE TABLE speakers(
        id             TEXT    PRIMARY KEY,
        label          TEXT    NOT NULL,
        firstSeen      INTEGER NOT NULL,
        centroid       TEXT    NOT NULL,
        embeddingCount INTEGER NOT NULL DEFAULT 1
      )
    ''');
  }

  static Future<void> _onUpgrade(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    _log.info('Upgrading database from v$oldVersion to v$newVersion');
    if (oldVersion < 2) {
      await db.execute('''
        CREATE TABLE speakers(
          id             TEXT    PRIMARY KEY,
          label          TEXT    NOT NULL,
          firstSeen      INTEGER NOT NULL,
          centroid       TEXT    NOT NULL,
          embeddingCount INTEGER NOT NULL DEFAULT 1
        )
      ''');
    }
  }

  static Future<void> _onOpen(Database db) async {
    final cutoff = DateTime.now()
        .subtract(const Duration(days: 30))
        .millisecondsSinceEpoch;
    final deleted = await db.delete(
      'reminders',
      where: "status IN ('confirmed','dismissed') AND created_at < ?",
      whereArgs: [cutoff],
    );
    if (deleted > 0) {
      _log.info('Auto-cleanup removed $deleted old reminders');
    }
  }
}
