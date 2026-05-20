import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:sqflite/sqflite.dart';

import 'package:murmur/core/result.dart';
import 'package:murmur/data/database/app_database.dart';
import 'package:murmur/data/models/reminder.dart';

final reminderDaoProvider = Provider<ReminderDao>((ref) => ReminderDao());

final _log = Logger('ReminderDao');

class ReminderDao {
  Future<Database> get _db => AppDatabase.database;

  Future<Result<int>> insert(Reminder reminder) async {
    try {
      final db = await _db;
      final id = await db.insert(
        'reminders',
        reminder.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      return Ok(id);
    } catch (e, st) {
      _log.severe('insert failed', e, st);
      return Err('Failed to insert reminder: $e', cause: e as Object);
    }
  }

  Future<Result<List<Reminder>>> queryByStatus(ReminderStatus status) async {
    try {
      final db = await _db;
      final rows = await db.query(
        'reminders',
        where: 'status = ?',
        whereArgs: [status.name],
        orderBy: 'created_at DESC',
      );
      return Ok(rows.map(Reminder.fromMap).toList());
    } catch (e, st) {
      _log.severe('queryByStatus failed', e, st);
      return Err('Failed to query reminders: $e', cause: e as Object);
    }
  }

  Future<Result<List<Reminder>>> queryAll({int limit = 100}) async {
    try {
      final db = await _db;
      final rows = await db.query(
        'reminders',
        orderBy: 'created_at DESC',
        limit: limit,
      );
      return Ok(rows.map(Reminder.fromMap).toList());
    } catch (e, st) {
      _log.severe('queryAll failed', e, st);
      return Err('Failed to query reminders: $e', cause: e as Object);
    }
  }

  Future<Result<void>> updateStatus(int id, ReminderStatus status) async {
    try {
      final db = await _db;
      await db.update(
        'reminders',
        {'status': status.name},
        where: 'id = ?',
        whereArgs: [id],
      );
      return const Ok(null);
    } catch (e, st) {
      _log.severe('updateStatus failed', e, st);
      return Err('Failed to update reminder status: $e', cause: e as Object);
    }
  }

  Future<Result<void>> delete(int id) async {
    try {
      final db = await _db;
      await db.delete('reminders', where: 'id = ?', whereArgs: [id]);
      return const Ok(null);
    } catch (e, st) {
      _log.severe('delete failed', e, st);
      return Err('Failed to delete reminder: $e', cause: e as Object);
    }
  }
}
