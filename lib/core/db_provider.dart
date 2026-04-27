// lib/core/db_provider.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'db_schema.dart';

class DBProvider {
  DBProvider._privateConstructor();
  static final DBProvider db = DBProvider._privateConstructor();
  static const String _dbName = 'family_calendar.db';
  static const int _dbVersion = DBSchema.version; // 16
  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB();
    return _database!;
  }

  Future<Database> _initDB() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = join(dir.path, _dbName);
    debugPrint('SQLite path: $path');
    return await openDatabase(
      path,
      version: _dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  FutureOr<void> _onCreate(Database db, int version) async {
    await db.execute(DBSchema.createUsers);
    await db.execute(DBSchema.createEvents);
    await db.execute(DBSchema.createChecklist);
    await db.execute(DBSchema.createShifts);
    await db.execute(DBSchema.createShiftAssignments);
    await db.execute(DBSchema.createJokes);
    await db.execute(DBSchema.createPhrases);
    await db.execute(DBSchema.createLanguageWords);
    await db.execute(DBSchema.createFacts);
    await db.execute(DBSchema.createFriends);
    await db.execute(DBSchema.createWeeklyMenus);
    await db.execute(DBSchema.createWeeklyTasks);
  }

  FutureOr<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    for (var v = oldVersion + 1; v <= newVersion; v++) {
      switch (v) {
        case 2:
          await db.execute('DROP TABLE IF EXISTS ${DBSchema.tableEvents}');
          await db.execute(DBSchema.createEvents);
          break;
        case 3:
          await db.execute(DBSchema.createChecklist);
          break;
        case 4:
          await db.execute(DBSchema.createShifts);
          break;
        case 5:
          await db.execute(DBSchema.createShiftAssignments);
          break;
        case 6:
          for (final col in [
            'has_alarm INTEGER NOT NULL DEFAULT 0',
            'alarm_at INTEGER',
            'has_notification INTEGER NOT NULL DEFAULT 0',
            'notification_at INTEGER',
          ]) {
            await db.execute(
              'ALTER TABLE ${DBSchema.tableEvents} ADD COLUMN $col',
            );
          }
          debugPrint('Migración v6: alarmas añadidas a eventos');
          break;
        case 7:
          await db.execute(
            'ALTER TABLE ${DBSchema.tableEvents} ADD COLUMN solo_para_mi INTEGER NOT NULL DEFAULT 0',
          );
          debugPrint('Migración v7: solo_para_mi añadido');
          break;
        case 8:
          await db.execute(DBSchema.createFriends);
          debugPrint('Migración v8: tabla friends creada');
          break;
        case 9:
          await db.execute(
            'ALTER TABLE ${DBSchema.tableEvents} ADD COLUMN owner_id TEXT',
          );
          debugPrint('Migración v9: owner_id en eventos');
          break;
        case 10:
          await db.execute(DBSchema.createJokes);
          await db.execute(DBSchema.createPhrases);
          await db.execute(DBSchema.createLanguageWords);
          await db.execute(DBSchema.createFacts);
          debugPrint('Migración v10: tablas contenido diario creadas');
          break;
        case 11:
          await db.execute(
            "ALTER TABLE ${DBSchema.tableFriends} ADD COLUMN alias TEXT NOT NULL DEFAULT ''",
          );
          await db.execute(
            "ALTER TABLE ${DBSchema.tableFriends} ADD COLUMN logo TEXT NOT NULL DEFAULT '😊'",
          );
          await db.execute(
            'ALTER TABLE ${DBSchema.tableFriends} ADD COLUMN firebase_uid TEXT',
          );
          debugPrint('Migración v11: amigos con alias/logo/uid');
          break;
        case 12:
          for (final col in [
            "shift_name TEXT NOT NULL DEFAULT ''",
            'shift_color INTEGER NOT NULL DEFAULT 4280391411',
            'shift_from_minutes INTEGER NOT NULL DEFAULT 0',
            'shift_to_minutes INTEGER NOT NULL DEFAULT 0',
          ]) {
            await db.execute(
              'ALTER TABLE ${DBSchema.tableShiftAssignments} ADD COLUMN $col',
            );
          }
          debugPrint('Migración v12: shift_assignments enriquecido');
          break;
        case 13:
          await db.execute('DROP TABLE IF EXISTS ${DBSchema.tableChecklist}');
          await db.execute(DBSchema.createChecklist);
          debugPrint(
            'Migración v13: checklist_items.id cambiado a TEXT PRIMARY KEY',
          );
          break;
        case 14:
          await db.execute(DBSchema.createWeeklyMenus);
          debugPrint('Migración v14: tabla weekly_menus creada');
          break;
        case 15:
          await db.execute(DBSchema.createWeeklyTasks);
          debugPrint('Migración v15: tabla weekly_tasks creada');
          break;
        // ── v16: columnas de compartir en weekly_menus y weekly_tasks ──────────
        case 16:
          for (final col in [
            "owner_name TEXT NOT NULL DEFAULT ''",
            "shared_with TEXT NOT NULL DEFAULT ''",
          ]) {
            await db.execute(
              'ALTER TABLE ${DBSchema.tableWeeklyMenus} ADD COLUMN $col',
            );
            await db.execute(
              'ALTER TABLE ${DBSchema.tableWeeklyTasks} ADD COLUMN $col',
            );
          }
          debugPrint(
            'Migración v16: shared_with y owner_name en tablas semanales',
          );
          break;
      }
    }
  }

  Future<void> insertOrReplace(
    String table,
    Map<String, dynamic> values,
  ) async {
    final c = await database;
    await c.insert(table, values, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> batchInsert(
    String table,
    List<Map<String, dynamic>> rows,
  ) async {
    if (rows.isEmpty) return;
    final c = await database;
    final batch = c.batch();
    for (final r in rows) {
      batch.insert(table, r, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> query(
    String table, {
    String? where,
    List<dynamic>? whereArgs,
    String? orderBy,
    String? limit,
  }) async {
    final c = await database;
    return c.rawQuery(
      'SELECT * FROM $table'
      '${where != null ? ' WHERE $where' : ''}'
      '${orderBy != null ? ' ORDER BY $orderBy' : ''}'
      '${limit != null ? ' LIMIT $limit' : ''}',
      whereArgs,
    );
  }

  Future<int> delete(
    String table, {
    required String where,
    required List<dynamic> whereArgs,
  }) async {
    final c = await database;
    return c.delete(table, where: where, whereArgs: whereArgs);
  }

  Future<List<Map<String, dynamic>>> getAll(String table) async {
    final c = await database;
    return c.query(table);
  }

  Future<int> count(String table) async {
    final c = await database;
    final res = await c.rawQuery('SELECT COUNT(*) as cnt FROM $table');
    return Sqflite.firstIntValue(res) ?? 0;
  }

  Future<void> reset() async {
    await _database?.close();
    _database = null;
  }
}
