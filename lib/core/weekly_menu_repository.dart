// lib/core/weekly_menu_repository.dart

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/weekly_menu_model.dart';
import 'db_provider.dart';
import 'db_schema.dart';
import 'weekly_share_service.dart';
import 'dismissed_shared_service.dart';
import 'shared_date_override_service.dart';
import 'date_change_service.dart';

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
    return _queryRange(
      monday.millisecondsSinceEpoch,
      sunday.millisecondsSinceEpoch,
    );
  }

  /// Devuelve todos los menús (propios y compartidos conmigo) cuyo día cae
  /// dentro del mes de [anyDayInMonth].
  Future<List<WeeklyMenuEntry>> getEntriesForMonth(
    DateTime anyDayInMonth,
  ) async {
    final firstDay = DateTime(anyDayInMonth.year, anyDayInMonth.month, 1);
    // Día 0 del mes siguiente = último día de este mes.
    final lastDay = DateTime(
      anyDayInMonth.year,
      anyDayInMonth.month + 1,
      0,
      23,
      59,
      59,
    );
    return _queryRange(
      firstDay.millisecondsSinceEpoch,
      lastDay.millisecondsSinceEpoch,
    );
  }

  /// Lectura común: aplica la fecha local (override) de los menús compartidos
  /// que yo haya movido de día.
  Future<List<WeeklyMenuEntry>> _queryRange(int fromMs, int toMs) async {
    final dismissed = await DismissedSharedService.instance.idsForType('menus');
    final overrides = await SharedDateOverrideService.instance.mapForType(
      'menus',
    );

    final (whereSql, whereArgs) = SharedDateOverrideService.buildRangeWhere(
      fromMs: fromMs,
      toMs: toMs,
      overrides: overrides,
    );

    final rows = await DBProvider.db.query(
      DBSchema.tableWeeklyMenus,
      where: whereSql,
      whereArgs: whereArgs,
    );

    // Si el dueño ya aceptó la propuesta, mi override sobra.
    await SharedDateOverrideService.instance.reconcile('menus', {
      for (final r in rows) (r['id'] as String): (r['date'] as int),
    });

    final list = rows
        .map(WeeklyMenuEntry.fromMap)
        .map((e) {
          final ov = overrides[e.id];
          return ov == null ? e : e.copyWith(date: ov);
        })
        .where(
          (e) =>
              (e.ownerId == _uid || _isSharedWithMe(e.sharedWith)) &&
              !dismissed.contains(e.id) &&
              e.date >= fromMs &&
              e.date <= toMs,
        )
        .toList();

    list.sort((a, b) {
      final c = a.date.compareTo(b.date);
      return c != 0 ? c : a.mealType.compareTo(b.mealType);
    });
    return list;
  }

  bool _isSharedWithMe(String sharedWith) {
    if (sharedWith.isEmpty) return false;
    return sharedWith.contains('"$_uid"');
  }

  /// Mueve un menú a otro día.
  ///
  /// · Menú PROPIO      → cambia la fecha real y se sincroniza con todos.
  /// · Menú COMPARTIDO  → se me aplica YA a mí (override local) y se envía una
  ///   propuesta al dueño y al resto, que deciden si la aceptan.
  Future<void> moveToDay(WeeklyMenuEntry entry, DateTime newDay) async {
    final newDate = DateTime(
      newDay.year,
      newDay.month,
      newDay.day,
    ).millisecondsSinceEpoch;
    if (newDate == entry.date) return;

    final bool isForeign = entry.ownerId.isNotEmpty && entry.ownerId != _uid;

    if (isForeign) {
      await SharedDateOverrideService.instance.setOverride(
        entry.id,
        'menus',
        newDate,
      );
      final audience = <String>{
        entry.ownerId,
        ...WeeklyShareService.parseUids(entry.sharedWith),
      };
      await DateChangeService.instance.propose(
        itemId: entry.id,
        itemType: 'menus',
        itemTitle: entry.title,
        ownerId: entry.ownerId,
        oldDateMs: entry.date,
        newDateMs: newDate,
        audience: audience,
      );
      return;
    }

    await SharedDateOverrideService.instance.clear(entry.id, 'menus');
    await save(entry.copyWith(date: newDate, synced: 0));
  }

  /// Guarda un nuevo entry o actualiza uno existente.
  Future<void> save(WeeklyMenuEntry entry) async {
    final bool isMine = entry.ownerId.isEmpty || entry.ownerId == _uid;

    // ── Menú compartido POR OTRA persona ──────────────────────────────────────
    if (!isMine) {
      await DBProvider.db.insertOrReplace(
        DBSchema.tableWeeklyMenus,
        entry.copyWith(synced: 0).toMap(),
      );
      try {
        await _pushContentOnly(entry);
      } catch (e) {
        debugPrint('⚠️ contenido de menú no sincronizado (ajeno): $e');
      }
      return;
    }

    // ── Menú PROPIO ───────────────────────────────────────────────────────────
    // shared_with = UNIÓN de lo ya compartido en este item + reparto global.
    // Así los compartidos individuales NO se pierden al editar/guardar.
    final globalUids = await WeeklyShareService.instance.getSharedUidsForType(
      'menus',
    );
    final merged = WeeklyShareService.parseUids(entry.sharedWith)
      ..addAll(globalUids);
    final sharedJson = WeeklyShareService.uidsToJson(merged);

    final toSave = entry.copyWith(
      ownerId: _uid,
      ownerName: _displayName,
      sharedWith: sharedJson,
      synced: 0,
    );
    await DBProvider.db.insertOrReplace(
      DBSchema.tableWeeklyMenus,
      toSave.toMap(),
    );
    _pushToFirebase(toSave, merged.toList());
  }

  Future<void> delete(String id) async {
    // ¿Es un menú compartido POR OTRA persona? Entonces solo lo ocultamos
    // para mí (no se borra en Firebase ni para el dueño).
    final rows = await DBProvider.db.query(
      DBSchema.tableWeeklyMenus,
      where: 'id = ?',
      whereArgs: [id],
      limit: '1',
    );
    final ownerId = rows.isEmpty
        ? ''
        : (rows.first['owner_id'] as String? ?? '');
    final bool isShared = ownerId.isNotEmpty && ownerId != _uid;

    await DBProvider.db.delete(
      DBSchema.tableWeeklyMenus,
      where: 'id = ?',
      whereArgs: [id],
    );

    if (isShared) {
      await DismissedSharedService.instance.dismiss(id, 'menus');
    } else {
      _deleteFromFirebase(id);
    }
  }

  Future<void> deleteWeek(DateTime weekStart) async {
    final monday = _mondayOf(weekStart);
    final sunday = monday.add(
      const Duration(days: 6, hours: 23, minutes: 59, seconds: 59),
    );

    // 1) Míos → borrado real (local + Firebase)
    final mine = await DBProvider.db.query(
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
    for (final row in mine) _deleteFromFirebase(row['id'] as String);

    // 2) Compartidos conmigo → solo ocultar
    await _dismissSharedInRange(
      monday.millisecondsSinceEpoch,
      sunday.millisecondsSinceEpoch,
    );
  }

  Future<void> deleteDay(DateTime day) async {
    final midnight = DateTime(day.year, day.month, day.day);
    final endOfDay = midnight.add(
      const Duration(hours: 23, minutes: 59, seconds: 59),
    );

    // 1) Míos → borrado real
    final mine = await DBProvider.db.query(
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
    for (final row in mine) _deleteFromFirebase(row['id'] as String);

    // 2) Compartidos conmigo → solo ocultar
    await _dismissSharedInRange(
      midnight.millisecondsSinceEpoch,
      endOfDay.millisecondsSinceEpoch,
    );
  }

  /// Oculta (no borra) los menús compartidos por otros dentro del rango.
  Future<void> _dismissSharedInRange(int fromMs, int toMs) async {
    final shared = await DBProvider.db.query(
      DBSchema.tableWeeklyMenus,
      where: 'date >= ? AND date <= ? AND owner_id != ? AND owner_id != ?',
      whereArgs: [fromMs, toMs, _uid, ''],
    );
    final ids = shared
        .map((r) => r['id'] as String)
        .where((id) => id.isNotEmpty)
        .toList();
    if (ids.isEmpty) return;
    await DismissedSharedService.instance.dismissAll(ids, 'menus');
    // También los quitamos de local para que desaparezcan al instante.
    for (final id in ids) {
      await DBProvider.db.delete(
        DBSchema.tableWeeklyMenus,
        where: 'id = ?',
        whereArgs: [id],
      );
    }
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
        'shared_with': sharedUids,
        'updated_at': FieldValue.serverTimestamp(),
      };
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

  Future<void> _pushContentOnly(WeeklyMenuEntry entry) async {
    if (_uid.isEmpty) return;
    await _firestore.collection(_collection).doc(entry.id).set({
      'meal_type': entry.mealType,
      'title': entry.title,
      'description': entry.description,
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await DBProvider.db.insertOrReplace(
      DBSchema.tableWeeklyMenus,
      entry.copyWith(synced: 1).toMap(),
    );
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

  static int _idCounter = 0;
  String generateId() =>
      'wm_${_uid}_${DateTime.now().microsecondsSinceEpoch}_${_idCounter++}';

  String _listToJson(dynamic raw) {
    if (raw == null) return '';
    final list = raw as List<dynamic>;
    if (list.isEmpty) return '';
    return '[${list.map((e) => '"$e"').join(',')}]';
  }
}
