// lib/core/weekly_menu_repository.dart

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/weekly_menu_model.dart';
import 'db_provider.dart';
import 'db_schema.dart';
import 'weekly_share_service.dart';

class WeeklyMenuRepository {
  WeeklyMenuRepository._();
  static final WeeklyMenuRepository instance = WeeklyMenuRepository._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const String _collection = 'weekly_menus';

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';
  String get _displayName =>
      FirebaseAuth.instance.currentUser?.displayName ??
      FirebaseAuth.instance.currentUser?.email ??
      '';

  // ══════════════════════════════════════════════════════════════════════════
  // LOCAL (SQLite) — incluye items propios y compartidos conmigo
  // ══════════════════════════════════════════════════════════════════════════

  Future<List<WeeklyMenuEntry>> getEntriesForWeek(DateTime weekStart) async {
    final monday = _mondayOf(weekStart);
    final sunday = monday.add(
      const Duration(days: 6, hours: 23, minutes: 59, seconds: 59),
    );

    final rows = await DBProvider.db.query(
      DBSchema.tableWeeklyMenus,
      // Traer propios Y compartidos conmigo (owner_id distinto = compartido)
      where: 'date >= ? AND date <= ? AND (owner_id = ? OR owner_id != "")',
      whereArgs: [
        monday.millisecondsSinceEpoch,
        sunday.millisecondsSinceEpoch,
        _uid,
      ],
      orderBy: 'date ASC, meal_type ASC',
    );

    // Filtrar: propios + los que tienen mi uid en shared_with local
    return rows
        .map(WeeklyMenuEntry.fromMap)
        .where((e) => e.ownerId == _uid || _isSharedWithMe(e.sharedWith))
        .toList();
  }

  bool _isSharedWithMe(String sharedWith) {
    if (sharedWith.isEmpty) return false;
    return sharedWith.contains('"$_uid"');
  }

  /// Guarda un nuevo entry o actualiza uno existente.
  /// Incluye automáticamente shared_with de la configuración activa.
  Future<void> save(WeeklyMenuEntry entry) async {
    final sharedUids = await WeeklyShareService.instance.getSharedUidsForType(
      'menus',
    );
    final sharedJson = sharedUids.isEmpty
        ? ''
        : '[${sharedUids.map((u) => '"$u"').join(',')}]';

    final toSave = entry.copyWith(
      ownerId: _uid,
      ownerName: _displayName,
      sharedWith: entry.ownerId == _uid || entry.ownerId.isEmpty
          ? sharedJson
          : entry.sharedWith,
      synced: 0,
    );
    await DBProvider.db.insertOrReplace(
      DBSchema.tableWeeklyMenus,
      toSave.toMap(),
    );
    _pushToFirebase(toSave, sharedUids);
  }

  Future<void> delete(String id) async {
    await DBProvider.db.delete(
      DBSchema.tableWeeklyMenus,
      where: 'id = ?',
      whereArgs: [id],
    );
    _deleteFromFirebase(id);
  }

  Future<void> deleteWeek(DateTime weekStart) async {
    final monday = _mondayOf(weekStart);
    final sunday = monday.add(
      const Duration(days: 6, hours: 23, minutes: 59, seconds: 59),
    );

    final rows = await DBProvider.db.query(
      DBSchema.tableWeeklyMenus,
      where: 'date >= ? AND date <= ? AND owner_id = ?',
      whereArgs: [
        monday.millisecondsSinceEpoch,
        sunday.millisecondsSinceEpoch,
        _uid,
      ],
    );
    await DBProvider.db.delete(
      DBSchema.tableWeeklyMenus,
      where: 'date >= ? AND date <= ? AND owner_id = ?',
      whereArgs: [
        monday.millisecondsSinceEpoch,
        sunday.millisecondsSinceEpoch,
        _uid,
      ],
    );
    for (final row in rows) _deleteFromFirebase(row['id'] as String);
  }

  Future<void> deleteDay(DateTime day) async {
    final midnight = DateTime(day.year, day.month, day.day);
    final endOfDay = midnight.add(
      const Duration(hours: 23, minutes: 59, seconds: 59),
    );

    final rows = await DBProvider.db.query(
      DBSchema.tableWeeklyMenus,
      where: 'date >= ? AND date <= ? AND owner_id = ?',
      whereArgs: [
        midnight.millisecondsSinceEpoch,
        endOfDay.millisecondsSinceEpoch,
        _uid,
      ],
    );
    await DBProvider.db.delete(
      DBSchema.tableWeeklyMenus,
      where: 'date >= ? AND date <= ? AND owner_id = ?',
      whereArgs: [
        midnight.millisecondsSinceEpoch,
        endOfDay.millisecondsSinceEpoch,
        _uid,
      ],
    );
    for (final row in rows) _deleteFromFirebase(row['id'] as String);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // FIREBASE SYNC
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> pullFromFirebase() async {
    if (_uid.isEmpty) return;
    try {
      final snap = await _firestore
          .collection(_collection)
          .where('owner_id', isEqualTo: _uid)
          .get();
      if (snap.docs.isEmpty) return;

      final rows = snap.docs.map((d) {
        final data = d.data();
        return {
          'id': d.id,
          'date': (data['date'] as Timestamp?)?.millisecondsSinceEpoch ?? 0,
          'meal_type': data['meal_type'] ?? 'Comida',
          'title': data['title'] ?? '',
          'description': data['description'] ?? '',
          'owner_id': data['owner_id'] ?? _uid,
          'owner_name': data['owner_name'] ?? '',
          'shared_with': _listToJson(data['shared_with']),
          'synced': 1,
        };
      }).toList();

      await DBProvider.db.batchInsert(DBSchema.tableWeeklyMenus, rows);
      debugPrint('📥 ${rows.length} menús semanales propios desde Firebase');
    } catch (e) {
      debugPrint('❌ Error pull weekly_menus: $e');
    }
  }

  Future<void> _pushToFirebase(
    WeeklyMenuEntry entry,
    List<String> sharedUids,
  ) async {
    if (_uid.isEmpty) return;
    try {
      final payload = <String, dynamic>{
        'date': Timestamp.fromMillisecondsSinceEpoch(entry.date),
        'meal_type': entry.mealType,
        'title': entry.title,
        'description': entry.description,
        'owner_id': _uid,
        'owner_name': _displayName,
        'updated_at': FieldValue.serverTimestamp(),
      };
      if (sharedUids.isNotEmpty) {
        payload['shared_with'] = sharedUids;
      }
      await _firestore
          .collection(_collection)
          .doc(entry.id)
          .set(payload, SetOptions(merge: true));
      await DBProvider.db.insertOrReplace(
        DBSchema.tableWeeklyMenus,
        entry.copyWith(synced: 1).toMap(),
      );
    } catch (e) {
      debugPrint('❌ Error push weekly_menu: $e');
    }
  }

  Future<void> _deleteFromFirebase(String id) async {
    if (_uid.isEmpty) return;
    try {
      await _firestore.collection(_collection).doc(id).delete();
    } catch (e) {
      debugPrint('❌ Error delete weekly_menu: $e');
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // UTILIDADES
  // ══════════════════════════════════════════════════════════════════════════

  DateTime _mondayOf(DateTime date) {
    final monday = date.subtract(Duration(days: date.weekday - 1));
    return DateTime(monday.year, monday.month, monday.day);
  }

  String generateId() => 'wm_${_uid}_${DateTime.now().millisecondsSinceEpoch}';

  String _listToJson(dynamic raw) {
    if (raw == null) return '';
    final list = raw as List<dynamic>;
    if (list.isEmpty) return '';
    return '[${list.map((e) => '"$e"').join(',')}]';
  }
}
