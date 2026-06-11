import 'package:logging/logging.dart';
import 'package:sqflite/sqflite.dart';

import 'package:murmur/data/database/app_database.dart';
import 'package:murmur/data/models/speaker.dart';

final _log = Logger('SpeakerDao');

class SpeakerDao {
  const SpeakerDao();

  Future<Database> get _database => AppDatabase.database;

  Future<void> upsert(Speaker speaker) async {
    try {
      final db = await _database;
      await db.insert(
        'speakers',
        speaker.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e, st) {
      _log.severe('upsert failed', e, st);
      rethrow;
    }
  }

  Future<List<Speaker>> queryAll() async {
    try {
      final db = await _database;
      final rows = await db.query('speakers', orderBy: 'firstSeen ASC');
      return rows.map(Speaker.fromMap).toList();
    } catch (e, st) {
      _log.severe('queryAll failed', e, st);
      rethrow;
    }
  }

  Future<void> updateLabel(String id, String label) async {
    try {
      final db = await _database;
      await db.update(
        'speakers',
        {'label': label},
        where: 'id = ?',
        whereArgs: [id],
      );
    } catch (e, st) {
      _log.severe('updateLabel failed', e, st);
      rethrow;
    }
  }

  Future<void> delete(String id) async {
    try {
      final db = await _database;
      await db.delete('speakers', where: 'id = ?', whereArgs: [id]);
    } catch (e, st) {
      _log.severe('delete failed', e, st);
      rethrow;
    }
  }

  Future<void> deleteAll() async {
    try {
      final db = await _database;
      await db.delete('speakers');
    } catch (e, st) {
      _log.severe('deleteAll failed', e, st);
      rethrow;
    }
  }
}
