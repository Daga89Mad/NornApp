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
  static const int _dbVersion = DBSchema.version; // 13
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
            "ALTER TABLE ${DBSchema.tableFriends} ADD COLUMN firebase_uid TEXT",
          );
          debugPrint('Migración v11: amigos con alias/logo/uid');
          break;
        case 12:
          await db.execute(
            "ALTER TABLE ${DBSchema.tableShiftAssignments} ADD COLUMN shift_name TEXT NOT NULL DEFAULT ''",
          );
          await db.execute(
            "ALTER TABLE ${DBSchema.tableShiftAssignments} ADD COLUMN shift_color INTEGER NOT NULL DEFAULT 4280391411",
          );
          await db.execute(
            "ALTER TABLE ${DBSchema.tableShiftAssignments} ADD COLUMN shift_from_minutes INTEGER NOT NULL DEFAULT 0",
          );
          await db.execute(
            "ALTER TABLE ${DBSchema.tableShiftAssignments} ADD COLUMN shift_to_minutes INTEGER NOT NULL DEFAULT 0",
          );
          debugPrint('Migración v12: shift_assignments enriquecido');
          break;

        // ── v13: corrige checklist_items.id de INTEGER AUTOINCREMENT a TEXT ──
        // La columna id antes era INTEGER PRIMARY KEY AUTOINCREMENT, pero
        // ChecklistRepository genera IDs de tipo String → datatype mismatch (error 20).
        // Solución: recrear la tabla con id TEXT PRIMARY KEY.
        // Los ítems anteriores (si los hubiera) se pierden; los eventos no se tocan.
        case 13:
          await db.execute('DROP TABLE IF EXISTS ${DBSchema.tableChecklist}');
          await db.execute(DBSchema.createChecklist);
          debugPrint(
            'Migración v13: checklist_items.id cambiado a TEXT PRIMARY KEY',
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

  /// Fuerza el cierre y reapertura de la conexión.
  /// Útil si la BD queda en estado inválido (SQLITE_READONLY_DBMOVED).
  Future<void> reset() async {
    await _database?.close();
    _database = null;
  }
}
