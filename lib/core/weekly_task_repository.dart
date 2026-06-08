// lib/core/weekly_task_repository.dart

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/weekly_task_model.dart';
import 'db_provider.dart';
import 'db_schema.dart';
import 'weekly_share_service.dart';

class WeeklyTaskRepository {
  WeeklyTaskRepository._();
  static final WeeklyTaskRepository instance = WeeklyTaskRepository._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const String _collection = 'weekly_tasks';

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';
  String get _displayName =>
      FirebaseAuth.instance.currentUser?.displayName ??
      FirebaseAuth.instance.currentUser?.email ??
      '';

  // ══════════════════════════════════════════════════════════════════════════
  // LOCAL (SQLite)
  // ══════════════════════════════════════════════════════════════════════════

  Future<List<WeeklyTask>> getTasksForWeek(DateTime weekStart) async {
    final monday = _mondayOf(weekStart);
    final sunday = monday.add(
      const Duration(days: 6, hours: 23, minutes: 59, seconds: 59),
    );

    final rows = await DBProvider.db.query(
      DBSchema.tableWeeklyTasks,
      where: 'date >= ? AND date <= ?',
      whereArgs: [monday.millisecondsSinceEpoch, sunday.millisecondsSinceEpoch],
      orderBy: 'date ASC, title ASC',
    );

    return rows
        .map(WeeklyTask.fromMap)
        .where((t) => t.ownerId == _uid || _isSharedWithMe(t.sharedWith))
        .toList();
  }

  bool _isSharedWithMe(String sharedWith) {
    if (sharedWith.isEmpty) return false;
    return sharedWith.contains('"$_uid"');
  }

  Future<void> save(WeeklyTask task) async {
    final bool isMine = task.ownerId.isEmpty || task.ownerId == _uid;

    // ── Tarea compartida POR OTRA persona ────────────────────────────────────
    if (!isMine) {
      // 1) Persistimos SIEMPRE el cambio local primero (fuente de verdad de la UI).
      await DBProvider.db.insertOrReplace(
        DBSchema.tableWeeklyTasks,
        task.copyWith(synced: 0).toMap(),
      );
      // 2) Sincronizamos solo el flag is_done; si falla, no rompe la UI.
      try {
        await _pushDoneFlagOnly(task);
      } catch (e) {
        debugPrint('⚠️ is_done no sincronizado (tarea ajena): $e');
      }
      return;
    }

    // ── Tarea PROPIA ──────────────────────────────────────────────────────────
    // 1) Guardado local PRIMERO, sin depender de la red.
    var toSave = task.copyWith(
      ownerId: _uid,
      ownerName: _displayName,
      synced: 0,
    );
    await DBProvider.db.insertOrReplace(
      DBSchema.tableWeeklyTasks,
      toSave.toMap(),
    );

    // 2) Reparto + push a Firebase; si algo falla, el cambio ya está en local.
    try {
      final sharedUids = await WeeklyShareService.instance.getSharedUidsForType(
        'tasks',
      );
      final sharedJson = sharedUids.isEmpty
          ? ''
          : '[${sharedUids.map((u) => '"$u"').join(',')}]';
      toSave = toSave.copyWith(sharedWith: sharedJson);
      await DBProvider.db.insertOrReplace(
        DBSchema.tableWeeklyTasks,
        toSave.toMap(),
      );
      await _pushToFirebase(toSave, sharedUids);
    } catch (e) {
      debugPrint('⚠️ Cambio guardado en local; falló la sincronización: $e');
    }
  }

  /// Para tareas ajenas: actualiza solo el estado de hecho/no hecho sin tocar
  /// owner_id ni shared_with, así el dueño no pierde la tarea ni el reparto.
  Future<void> _pushDoneFlagOnly(WeeklyTask task) async {
    if (_uid.isEmpty) return;
    try {
      await _firestore.collection(_collection).doc(task.id).set({
        'is_done': task.isDone,
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      await DBProvider.db.insertOrReplace(
        DBSchema.tableWeeklyTasks,
        task.copyWith(synced: 1).toMap(),
      );
    } catch (e) {
      debugPrint('❌ Error push is_done (tarea compartida): $e');
    }
  }

  /// Reaplica el reparto actual a TODAS mis tareas locales y las reempuja.
  /// Llamar al cerrar el diálogo de compartir y al abrir la pantalla, para que
  /// el otro usuario siempre vea las tareas sin tener que volver a compartir.
  Future<void> reapplyShares() async {
    if (_uid.isEmpty) return;
    final sharedUids = await WeeklyShareService.instance.getSharedUidsForType(
      'tasks',
    );
    final sharedJson = sharedUids.isEmpty
        ? ''
        : '[${sharedUids.map((u) => '"$u"').join(',')}]';

    final rows = await DBProvider.db.query(
      DBSchema.tableWeeklyTasks,
      where: 'owner_id = ?',
      whereArgs: [_uid],
    );
    for (final row in rows) {
      final t = WeeklyTask.fromMap(
        row,
      ).copyWith(sharedWith: sharedJson, synced: 0);
      await DBProvider.db.insertOrReplace(DBSchema.tableWeeklyTasks, t.toMap());
      await _pushToFirebase(t, sharedUids);
    }
    debugPrint('🔁 Reaplicado reparto a ${rows.length} tareas');
  }

  Future<void> toggleDone(WeeklyTask task) async {
    await save(task.copyWith(isDone: !task.isDone));
  }

  Future<void> delete(String id) async {
    await DBProvider.db.delete(
      DBSchema.tableWeeklyTasks,
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
      DBSchema.tableWeeklyTasks,
      where: 'date >= ? AND date <= ? AND owner_id = ?',
      whereArgs: [
        monday.millisecondsSinceEpoch,
        sunday.millisecondsSinceEpoch,
        _uid,
      ],
    );
    await DBProvider.db.delete(
      DBSchema.tableWeeklyTasks,
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
      DBSchema.tableWeeklyTasks,
      where: 'date >= ? AND date <= ? AND owner_id = ?',
      whereArgs: [
        midnight.millisecondsSinceEpoch,
        endOfDay.millisecondsSinceEpoch,
        _uid,
      ],
    );
    await DBProvider.db.delete(
      DBSchema.tableWeeklyTasks,
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
          'title': data['title'] ?? '',
          'description': data['description'] ?? '',
          'is_done': (data['is_done'] ?? false) ? 1 : 0,
          'owner_id': data['owner_id'] ?? _uid,
          'owner_name': data['owner_name'] ?? '',
          'shared_with': _listToJson(data['shared_with']),
          'synced': 1,
        };
      }).toList();

      await DBProvider.db.batchInsert(DBSchema.tableWeeklyTasks, rows);
      debugPrint('📥 ${rows.length} tareas semanales propias desde Firebase');
    } catch (e) {
      debugPrint('❌ Error pull weekly_tasks: $e');
    }
  }

  Future<void> _pushToFirebase(WeeklyTask task, List<String> sharedUids) async {
    if (_uid.isEmpty) return;
    try {
      final payload = <String, dynamic>{
        'date': Timestamp.fromMillisecondsSinceEpoch(task.date),
        'title': task.title,
        'description': task.description,
        'is_done': task.isDone,
        'owner_id': _uid,
        'owner_name': _displayName,
        'updated_at': FieldValue.serverTimestamp(),
      };
      payload['shared_with'] = sharedUids;
      await _firestore
          .collection(_collection)
          .doc(task.id)
          .set(payload, SetOptions(merge: true));
      await DBProvider.db.insertOrReplace(
        DBSchema.tableWeeklyTasks,
        task.copyWith(synced: 1).toMap(),
      );
    } catch (e) {
      debugPrint('❌ Error push weekly_task: $e');
    }
  }

  Future<void> _deleteFromFirebase(String id) async {
    if (_uid.isEmpty) return;
    try {
      await _firestore.collection(_collection).doc(id).delete();
    } catch (e) {
      debugPrint('❌ Error delete weekly_task: $e');
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // UTILIDADES
  // ══════════════════════════════════════════════════════════════════════════

  DateTime _mondayOf(DateTime date) {
    final monday = date.subtract(Duration(days: date.weekday - 1));
    return DateTime(monday.year, monday.month, monday.day);
  }

  String generateId() => 'wt_${_uid}_${DateTime.now().millisecondsSinceEpoch}';

  String _listToJson(dynamic raw) {
    if (raw == null) return '';
    final list = raw as List<dynamic>;
    if (list.isEmpty) return '';
    return '[${list.map((e) => '"$e"').join(',')}]';
  }

  /// Crea la tarea y, si es recurrente, genera instancias futuras.
  /// 'weekly' → 12 semanas; 'daily' → 30 días.
  Future<void> saveWithRecurrence(WeeklyTask task) async {
    await save(task);
    if (task.recurrence == 'none') return;

    final base = DateTime.fromMillisecondsSinceEpoch(task.date);
    final int count = task.recurrence == 'weekly' ? 11 : 29;
    final Duration step = task.recurrence == 'weekly'
        ? const Duration(days: 7)
        : const Duration(days: 1);

    for (var i = 1; i <= count; i++) {
      final d = base.add(step * i);
      final instance = task.copyWith(
        id: generateId(),
        date: DateTime(d.year, d.month, d.day).millisecondsSinceEpoch,
        isDone: false,
        synced: 0,
      );
      await save(instance);
    }
  }

  /// Mueve una tarea a otro día (cambia su fecha).
  Future<void> moveToDay(WeeklyTask task, DateTime newDay) async {
    await save(
      task.copyWith(
        date: DateTime(
          newDay.year,
          newDay.month,
          newDay.day,
        ).millisecondsSinceEpoch,
        synced: 0,
      ),
    );
  }
}
