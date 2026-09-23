// lib/core/weekly_task_repository.dart

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/weekly_task_model.dart';
import 'db_provider.dart';
import 'db_schema.dart';
import 'weekly_share_service.dart';
import 'dismissed_shared_service.dart';
import 'shared_date_override_service.dart';
import 'date_change_service.dart';
import 'week_dates.dart';
import 'recurrence_rule.dart';

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

  /// Devuelve TODAS las tareas de la semana (principales y subtareas),
  /// aplicando la fecha local (override) de las tareas compartidas que yo haya
  /// movido de día.
  Future<List<WeeklyTask>> getTasksForWeek(DateTime weekStart) async {
    final monday = mondayOf(weekStart);
    final fromMs = monday.millisecondsSinceEpoch;
    final toMs = endOfWeekMs(monday);

    final dismissed = await DismissedSharedService.instance.idsForType('tasks');
    final overrides = await SharedDateOverrideService.instance.mapForType(
      'tasks',
    );

    final (whereSql, whereArgs) = SharedDateOverrideService.buildRangeWhere(
      fromMs: fromMs,
      toMs: toMs,
      overrides: overrides,
    );

    final rows = await DBProvider.db.query(
      DBSchema.tableWeeklyTasks,
      where: whereSql,
      whereArgs: whereArgs,
    );

    // Si el dueño ya aceptó la propuesta, la fecha real coincide con mi
    // override y este deja de tener sentido: se limpia.
    await SharedDateOverrideService.instance.reconcile('tasks', {
      for (final r in rows) (r['id'] as String): (r['date'] as int),
    });

    final list = rows
        .map(WeeklyTask.fromMap)
        .map((t) {
          final ov = overrides[t.id];
          return ov == null ? t : t.copyWith(date: ov);
        })
        .where(
          (t) =>
              (t.ownerId == _uid || _isSharedWithMe(t.sharedWith)) &&
              !dismissed.contains(t.id) &&
              t.date >= fromMs &&
              t.date <= toMs,
        )
        .toList();

    list.sort((a, b) {
      final c = a.date.compareTo(b.date);
      return c != 0 ? c : a.title.compareTo(b.title);
    });
    return list;
  }

  /// Subtareas de una tarea concreta (con fecha local aplicada).
  Future<List<WeeklyTask>> getSubtasks(String parentId) async {
    final dismissed = await DismissedSharedService.instance.idsForType('tasks');
    final overrides = await SharedDateOverrideService.instance.mapForType(
      'tasks',
    );
    final rows = await DBProvider.db.query(
      DBSchema.tableWeeklyTasks,
      where: 'parent_id = ?',
      whereArgs: [parentId],
      orderBy: 'title ASC',
    );
    return rows
        .map(WeeklyTask.fromMap)
        .map((t) {
          final ov = overrides[t.id];
          return ov == null ? t : t.copyWith(date: ov);
        })
        .where((t) => !dismissed.contains(t.id))
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
      await DBProvider.db.insertOrReplace(
        DBSchema.tableWeeklyTasks,
        task.copyWith(synced: 0).toMap(),
      );
      try {
        await _pushDoneFlagOnly(task);
      } catch (e) {
        debugPrint('⚠️ is_done no sincronizado (tarea ajena): $e');
      }
      return;
    }

    // ── Tarea PROPIA ──────────────────────────────────────────────────────────
    var toSave = task.copyWith(
      ownerId: _uid,
      ownerName: _displayName,
      synced: 0,
    );
    await DBProvider.db.insertOrReplace(
      DBSchema.tableWeeklyTasks,
      toSave.toMap(),
    );

    try {
      // shared_with = UNIÓN de lo ya compartido en el item + reparto global.
      final globalUids = await WeeklyShareService.instance.getSharedUidsForType(
        'tasks',
      );
      final merged = WeeklyShareService.parseUids(task.sharedWith)
        ..addAll(globalUids);
      final sharedJson = WeeklyShareService.uidsToJson(merged);
      toSave = toSave.copyWith(sharedWith: sharedJson);
      await DBProvider.db.insertOrReplace(
        DBSchema.tableWeeklyTasks,
        toSave.toMap(),
      );
      await _pushToFirebase(toSave, merged.toList());
    } catch (e) {
      debugPrint('⚠️ Cambio guardado en local; falló la sincronización: $e');
    }
  }

  /// Crea una subtarea colgando de [parent].
  Future<void> addSubtask(WeeklyTask parent, String title) async {
    final t = title.trim();
    if (t.isEmpty) return;
    final sub = WeeklyTask(
      id: generateId(),
      date: parent.date,
      title: t,
      description: '',
      isDone: false,
      ownerId: '', // save() lo marca como mío
      parentId: parent.id,
    );
    await save(sub);
  }

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

  /// Reaplica el reparto global a TODAS mis tareas, conservando además los
  /// compartidos individuales que cada tarea ya tuviera.
  Future<void> reapplyShares() async {
    if (_uid.isEmpty) return;
    final globalUids = await WeeklyShareService.instance.getSharedUidsForType(
      'tasks',
    );

    final rows = await DBProvider.db.query(
      DBSchema.tableWeeklyTasks,
      where: 'owner_id = ?',
      whereArgs: [_uid],
    );
    for (final row in rows) {
      final base = WeeklyTask.fromMap(row);
      final merged = WeeklyShareService.parseUids(base.sharedWith)
        ..addAll(globalUids);
      final t = base.copyWith(
        sharedWith: WeeklyShareService.uidsToJson(merged),
        synced: 0,
      );
      await DBProvider.db.insertOrReplace(DBSchema.tableWeeklyTasks, t.toMap());
      await _pushToFirebase(t, merged.toList());
    }
    debugPrint('🔁 Reaplicado reparto a ${rows.length} tareas');
  }

  Future<void> toggleDone(WeeklyTask task) async {
    await save(task.copyWith(isDone: !task.isDone));
  }

  /// Borra una tarea y, si es principal, también sus subtareas.
  /// Si la tarea es compartida por otro, solo se OCULTA (no se toca Firebase).
  Future<void> delete(String id) async {
    final rows = await DBProvider.db.query(
      DBSchema.tableWeeklyTasks,
      where: 'id = ?',
      whereArgs: [id],
      limit: '1',
    );
    final ownerId = rows.isEmpty
        ? ''
        : (rows.first['owner_id'] as String? ?? '');
    final bool isShared = ownerId.isNotEmpty && ownerId != _uid;

    // Subtareas asociadas
    final subs = await DBProvider.db.query(
      DBSchema.tableWeeklyTasks,
      where: 'parent_id = ?',
      whereArgs: [id],
    );

    if (isShared) {
      await DismissedSharedService.instance.dismiss(id, 'tasks');
      for (final s in subs) {
        await DismissedSharedService.instance.dismiss(
          s['id'] as String,
          'tasks',
        );
      }
    }

    for (final s in subs) {
      final sid = s['id'] as String;
      await DBProvider.db.delete(
        DBSchema.tableWeeklyTasks,
        where: 'id = ?',
        whereArgs: [sid],
      );
      if (!isShared) _deleteFromFirebase(sid);
    }
    await DBProvider.db.delete(
      DBSchema.tableWeeklyTasks,
      where: 'id = ?',
      whereArgs: [id],
    );
    if (!isShared) _deleteFromFirebase(id);
  }

  Future<void> deleteWeek(DateTime weekStart) async {
    final monday = mondayOf(weekStart);
    final fromMs = monday.millisecondsSinceEpoch;
    final toMs = endOfWeekMs(monday);

    final mine = await DBProvider.db.query(
      DBSchema.tableWeeklyTasks,
      where: 'date >= ? AND date <= ? AND owner_id = ?',
      whereArgs: [fromMs, toMs, _uid],
    );
    await DBProvider.db.delete(
      DBSchema.tableWeeklyTasks,
      where: 'date >= ? AND date <= ? AND owner_id = ?',
      whereArgs: [fromMs, toMs, _uid],
    );
    for (final row in mine) _deleteFromFirebase(row['id'] as String);

    await _dismissSharedInRange(fromMs, toMs);
  }

  Future<void> deleteDay(DateTime day) async {
    final fromMs = startOfDay(day).millisecondsSinceEpoch;
    final toMs = endOfDayMs(day);

    final mine = await DBProvider.db.query(
      DBSchema.tableWeeklyTasks,
      where: 'date >= ? AND date <= ? AND owner_id = ?',
      whereArgs: [fromMs, toMs, _uid],
    );
    await DBProvider.db.delete(
      DBSchema.tableWeeklyTasks,
      where: 'date >= ? AND date <= ? AND owner_id = ?',
      whereArgs: [fromMs, toMs, _uid],
    );
    for (final row in mine) _deleteFromFirebase(row['id'] as String);

    await _dismissSharedInRange(fromMs, toMs);
  }

  /// Oculta (no borra) las tareas compartidas por otros dentro del rango.
  Future<void> _dismissSharedInRange(int fromMs, int toMs) async {
    final shared = await DBProvider.db.query(
      DBSchema.tableWeeklyTasks,
      where: 'date >= ? AND date <= ? AND owner_id != ? AND owner_id != ?',
      whereArgs: [fromMs, toMs, _uid, ''],
    );
    final ids = shared
        .map((r) => r['id'] as String)
        .where((id) => id.isNotEmpty)
        .toList();
    if (ids.isEmpty) return;
    await DismissedSharedService.instance.dismissAll(ids, 'tasks');
    for (final id in ids) {
      await DBProvider.db.delete(
        DBSchema.tableWeeklyTasks,
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
          'title': data['title'] ?? '',
          'description': data['description'] ?? '',
          'is_done': (data['is_done'] ?? false) ? 1 : 0,
          'owner_id': data['owner_id'] ?? _uid,
          'owner_name': data['owner_name'] ?? '',
          'shared_with': _listToJson(data['shared_with']),
          'recurrence': data['recurrence'] ?? 'none',
          'parent_id': data['parent_id'] ?? '',
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
        'shared_with': sharedUids,
        'recurrence': task.recurrence,
        'parent_id': task.parentId,
        'updated_at': FieldValue.serverTimestamp(),
      };
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

  /// Lunes (medianoche) de la semana de [date].
  /// Delegado en week_dates para que sea seguro frente al cambio de hora:
  /// Duration suma tiempo absoluto y el día del cambio tiene 23 o 25 horas.
  DateTime _mondayOf(DateTime date) => mondayOf(date);

  static int _idCounter = 0;
  String generateId() =>
      'wt_${_uid}_${DateTime.now().microsecondsSinceEpoch}_${_idCounter++}';

  String _listToJson(dynamic raw) {
    if (raw == null) return '';
    final list = raw as List<dynamic>;
    if (list.isEmpty) return '';
    return '[${list.map((e) => '"$e"').join(',')}]';
  }

  /// Crea la tarea y, si es recurrente, genera una copia por cada fecha de
  /// la regla: cada día, cada semana, cada 2 semanas, cada mes o cada X días,
  /// desde la fecha de la tarea hasta rule.until.
  ///
  /// Si no se pasa [rule] se interpreta task.recurrence (compatibilidad con
  /// los valores antiguos 'daily' / 'weekly').
  /// Devuelve cuántas tareas se han creado en total.
  Future<int> saveWithRecurrence(
    WeeklyTask task, [
    RecurrenceRule? rule,
  ]) async {
    final r = rule ?? RecurrenceRule.decode(task.recurrence);
    final base = task.copyWith(recurrence: r.encode());
    await save(base);
    if (r.isNone) return 1;

    final dates = r
        .occurrences(DateTime.fromMillisecondsSinceEpoch(task.date))
        .skip(1) // la primera es la propia tarea
        .toList();

    const chunk = 8;
    for (var i = 0; i < dates.length; i += chunk) {
      final slice = dates.skip(i).take(chunk);
      await Future.wait(
        slice.map(
          (d) => save(
            base.copyWith(
              id: generateId(),
              date: d.millisecondsSinceEpoch,
              isDone: false,
              synced: 0,
            ),
          ),
        ),
      );
    }
    return dates.length + 1;
  }

  /// Mueve una tarea a otro día. Arrastra sus subtareas.
  ///
  /// · Tarea PROPIA      → cambia la fecha real y se sincroniza: todos los que
  ///   la tengan compartida la ven en el día nuevo.
  /// · Tarea COMPARTIDA  → el cambio se aplica YA en mi calendario (override
  ///   local) y se envía una propuesta al dueño y al resto de destinatarios,
  ///   que decidirán si la aceptan. Nunca se borra nada.
  Future<void> moveToDay(WeeklyTask task, DateTime newDay) async {
    final newDate = DateTime(
      newDay.year,
      newDay.month,
      newDay.day,
    ).millisecondsSinceEpoch;
    if (newDate == task.date) return;

    final bool isForeign = task.ownerId.isNotEmpty && task.ownerId != _uid;

    if (isForeign) {
      // 1) A mí se me cambia al instante.
      await SharedDateOverrideService.instance.setOverride(
        task.id,
        'tasks',
        newDate,
      );
      final subs = task.parentId.isEmpty
          ? await getSubtasks(task.id)
          : <WeeklyTask>[];
      for (final s in subs) {
        await SharedDateOverrideService.instance.setOverride(
          s.id,
          'tasks',
          newDate,
        );
      }

      // 2) Al dueño y al resto se les propone el cambio.
      final audience = <String>{
        task.ownerId,
        ...WeeklyShareService.parseUids(task.sharedWith),
      };
      await DateChangeService.instance.propose(
        itemId: task.id,
        itemType: 'tasks',
        itemTitle: task.title,
        ownerId: task.ownerId,
        oldDateMs: task.date,
        newDateMs: newDate,
        audience: audience,
      );
      return;
    }

    // Tarea propia: fecha real + push a Firebase.
    await SharedDateOverrideService.instance.clear(task.id, 'tasks');
    await save(task.copyWith(date: newDate, synced: 0));

    if (task.parentId.isEmpty) {
      final subs = await getSubtasks(task.id);
      for (final s in subs) {
        await SharedDateOverrideService.instance.clear(s.id, 'tasks');
        await save(s.copyWith(date: newDate, synced: 0));
      }
    }
  }
}
