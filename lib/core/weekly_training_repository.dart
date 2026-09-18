// lib/core/weekly_training_repository.dart

import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/weekly_training_model.dart';
import 'db_provider.dart';
import 'db_schema.dart';
import 'weekly_share_service.dart';
import 'dismissed_shared_service.dart';
import 'shared_date_override_service.dart';
import 'date_change_service.dart';
import 'week_dates.dart';

class WeeklyTrainingRepository {
  WeeklyTrainingRepository._();
  static final WeeklyTrainingRepository instance = WeeklyTrainingRepository._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const String _collection = 'weekly_trainings';

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';
  String get _displayName =>
      FirebaseAuth.instance.currentUser?.displayName ??
      FirebaseAuth.instance.currentUser?.email ??
      '';

  final List<StreamSubscription> _subscriptions = [];

  // ══════════════════════════════════════════════════════════════════════════
  // LOCAL (SQLite) — incluye items propios y compartidos conmigo
  // ══════════════════════════════════════════════════════════════════════════

  Future<List<WeeklyTrainingEntry>> getEntriesForWeek(
    DateTime weekStart,
  ) async {
    final monday = mondayOf(weekStart);
    final fromMs = monday.millisecondsSinceEpoch;
    final toMs = endOfWeekMs(monday);

    final dismissed = await DismissedSharedService.instance.idsForType(
      'trainings',
    );
    final overrides = await SharedDateOverrideService.instance.mapForType(
      'trainings',
    );

    final (whereSql, whereArgs) = SharedDateOverrideService.buildRangeWhere(
      fromMs: fromMs,
      toMs: toMs,
      overrides: overrides,
    );

    final rows = await DBProvider.db.query(
      DBSchema.tableWeeklyTrainings,
      where: whereSql,
      whereArgs: whereArgs,
    );

    // Si el dueño ya aceptó la propuesta, mi override sobra.
    await SharedDateOverrideService.instance.reconcile('trainings', {
      for (final r in rows) (r['id'] as String): (r['date'] as int),
    });

    final list = rows
        .map(WeeklyTrainingEntry.fromMap)
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
      return c != 0 ? c : a.trainingType.compareTo(b.trainingType);
    });
    return list;
  }

  bool _isSharedWithMe(String sharedWith) {
    if (sharedWith.isEmpty) return false;
    return sharedWith.contains('"$_uid"');
  }

  /// Mueve un entrenamiento a otro día.
  ///
  /// · PROPIO      → cambia la fecha real y se sincroniza con todos.
  /// · COMPARTIDO  → se me aplica YA a mí (override local) y se envía una
  ///   propuesta al dueño y al resto, que deciden si la aceptan.
  Future<void> moveToDay(WeeklyTrainingEntry entry, DateTime newDay) async {
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
        'trainings',
        newDate,
      );
      final audience = <String>{
        entry.ownerId,
        ...WeeklyShareService.parseUids(entry.sharedWith),
      };
      await DateChangeService.instance.propose(
        itemId: entry.id,
        itemType: 'trainings',
        itemTitle: entry.title,
        ownerId: entry.ownerId,
        oldDateMs: entry.date,
        newDateMs: newDate,
        audience: audience,
      );
      return;
    }

    await SharedDateOverrideService.instance.clear(entry.id, 'trainings');
    await save(entry.copyWith(date: newDate, synced: 0));
  }

  /// Guarda un nuevo entry o actualiza uno existente.
  Future<void> save(WeeklyTrainingEntry entry) async {
    final bool isMine = entry.ownerId.isEmpty || entry.ownerId == _uid;

    // ── Entrenamiento compartido POR OTRA persona ─────────────────────────────
    // Solo puedo tocar mi progreso (is_done), no el contenido.
    if (!isMine) {
      await DBProvider.db.insertOrReplace(
        DBSchema.tableWeeklyTrainings,
        entry.copyWith(synced: 0).toMap(),
      );
      try {
        await _pushDoneFlagOnly(entry);
      } catch (e) {
        debugPrint('⚠️ is_done no sincronizado (entrenamiento ajeno): $e');
      }
      return;
    }

    // ── Entrenamiento PROPIO ──────────────────────────────────────────────────
    var toSave = entry.copyWith(
      ownerId: _uid,
      ownerName: _displayName,
      synced: 0,
    );
    await DBProvider.db.insertOrReplace(
      DBSchema.tableWeeklyTrainings,
      toSave.toMap(),
    );

    try {
      // shared_with = UNIÓN de lo ya compartido en este item + reparto global.
      // Así los compartidos individuales NO se pierden al editar/guardar y los
      // nuevos entrenamientos heredan el "compartir toda la semana".
      final globalUids = await WeeklyShareService.instance.getSharedUidsForType(
        'trainings',
      );
      final merged = WeeklyShareService.parseUids(entry.sharedWith)
        ..addAll(globalUids);
      toSave = toSave.copyWith(
        sharedWith: WeeklyShareService.uidsToJson(merged),
      );
      await DBProvider.db.insertOrReplace(
        DBSchema.tableWeeklyTrainings,
        toSave.toMap(),
      );
      await _pushToFirebase(toSave);
    } catch (e) {
      debugPrint('⚠️ Cambio guardado en local; falló la sincronización: $e');
    }
  }

  /// Reaplica el reparto global a TODOS mis entrenamientos, conservando además
  /// los compartidos individuales que cada uno ya tuviera. Llamar tras abrir
  /// el diálogo de compartir.
  Future<void> reapplyShares() async {
    if (_uid.isEmpty) return;
    final globalUids = await WeeklyShareService.instance.getSharedUidsForType(
      'trainings',
    );
    final rows = await DBProvider.db.query(
      DBSchema.tableWeeklyTrainings,
      where: 'owner_id = ?',
      whereArgs: [_uid],
    );
    for (final row in rows) {
      final base = WeeklyTrainingEntry.fromMap(row);
      final merged = WeeklyShareService.parseUids(base.sharedWith)
        ..addAll(globalUids);
      final e = base.copyWith(
        sharedWith: WeeklyShareService.uidsToJson(merged),
        synced: 0,
      );
      await DBProvider.db.insertOrReplace(
        DBSchema.tableWeeklyTrainings,
        e.toMap(),
      );
      await _pushToFirebase(e);
    }
    debugPrint('🔁 Reaplicado reparto a ${rows.length} entrenamientos');
  }

  Future<void> toggleDone(WeeklyTrainingEntry entry) async {
    await save(entry.copyWith(isDone: !entry.isDone));
  }

  Future<void> delete(String id) async {
    final rows = await DBProvider.db.query(
      DBSchema.tableWeeklyTrainings,
      where: 'id = ?',
      whereArgs: [id],
      limit: '1',
    );
    final ownerId = rows.isEmpty
        ? ''
        : (rows.first['owner_id'] as String? ?? '');
    final bool isShared = ownerId.isNotEmpty && ownerId != _uid;

    await DBProvider.db.delete(
      DBSchema.tableWeeklyTrainings,
      where: 'id = ?',
      whereArgs: [id],
    );

    if (isShared) {
      await DismissedSharedService.instance.dismiss(id, 'trainings');
    } else {
      _deleteFromFirebase(id);
    }
  }

  Future<void> deleteWeek(DateTime weekStart) async {
    final monday = mondayOf(weekStart);
    final fromMs = monday.millisecondsSinceEpoch;
    final toMs = endOfWeekMs(monday);

    final mine = await DBProvider.db.query(
      DBSchema.tableWeeklyTrainings,
      where: 'date >= ? AND date <= ? AND owner_id = ?',
      whereArgs: [fromMs, toMs, _uid],
    );
    await DBProvider.db.delete(
      DBSchema.tableWeeklyTrainings,
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
      DBSchema.tableWeeklyTrainings,
      where: 'date >= ? AND date <= ? AND owner_id = ?',
      whereArgs: [fromMs, toMs, _uid],
    );
    await DBProvider.db.delete(
      DBSchema.tableWeeklyTrainings,
      where: 'date >= ? AND date <= ? AND owner_id = ?',
      whereArgs: [fromMs, toMs, _uid],
    );
    for (final row in mine) _deleteFromFirebase(row['id'] as String);

    await _dismissSharedInRange(fromMs, toMs);
  }

  /// Oculta (no borra) los entrenamientos compartidos por otros en el rango.
  Future<void> _dismissSharedInRange(int fromMs, int toMs) async {
    final shared = await DBProvider.db.query(
      DBSchema.tableWeeklyTrainings,
      where: 'date >= ? AND date <= ? AND owner_id != ? AND owner_id != ?',
      whereArgs: [fromMs, toMs, _uid, ''],
    );
    final ids = shared
        .map((r) => r['id'] as String)
        .where((id) => id.isNotEmpty)
        .toList();
    if (ids.isEmpty) return;
    await DismissedSharedService.instance.dismissAll(ids, 'trainings');
    for (final id in ids) {
      await DBProvider.db.delete(
        DBSchema.tableWeeklyTrainings,
        where: 'id = ?',
        whereArgs: [id],
      );
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // FIREBASE SYNC (mis propios entrenamientos entre mis dispositivos)
  // ══════════════════════════════════════════════════════════════════════════

  /// Descarga puntual (Firebase → SQLite) de mis entrenamientos. Llamar al
  /// abrir la pantalla.
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
          'training_type': data['training_type'] ?? 'Otro',
          'title': data['title'] ?? '',
          'description': data['description'] ?? '',
          'is_done': (data['is_done'] ?? false) ? 1 : 0,
          'owner_id': data['owner_id'] ?? _uid,
          'owner_name': data['owner_name'] ?? '',
          'shared_with': _listToJson(data['shared_with']),
          'synced': 1,
        };
      }).toList();

      await DBProvider.db.batchInsert(DBSchema.tableWeeklyTrainings, rows);
      debugPrint('📥 ${rows.length} entrenamientos propios desde Firebase');
    } catch (e) {
      debugPrint('❌ Error pull weekly_trainings: $e');
    }
  }

  /// Escucha en tiempo real mis entrenamientos (para reflejar cambios hechos
  /// desde otro dispositivo, p.ej. marcar/desmarcar completado) Y los
  /// entrenamientos que otros amigos comparten conmigo.
  void startListening({VoidCallback? onChanged}) {
    stopListening();
    if (_uid.isEmpty) return;

    Future<void> upsert(DocumentSnapshot<Map<String, dynamic>> doc) async {
      final data = doc.data();
      if (data == null) return;
      await DBProvider.db.insertOrReplace(DBSchema.tableWeeklyTrainings, {
        'id': doc.id,
        'date': (data['date'] as Timestamp?)?.millisecondsSinceEpoch ?? 0,
        'training_type': data['training_type'] ?? 'Otro',
        'title': data['title'] ?? '',
        'description': data['description'] ?? '',
        'is_done': (data['is_done'] ?? false) ? 1 : 0,
        'owner_id': data['owner_id'] ?? '',
        'owner_name': data['owner_name'] ?? '',
        'shared_with': _listToJson(data['shared_with']),
        'synced': 1,
      });
    }

    Future<void> remove(String id) async {
      await DBProvider.db.delete(
        DBSchema.tableWeeklyTrainings,
        where: 'id = ?',
        whereArgs: [id],
      );
    }

    // ── Mis entrenamientos PROPIOS ────────────────────────────────────────────
    final subOwn = _firestore
        .collection(_collection)
        .where('owner_id', isEqualTo: _uid)
        .snapshots()
        .listen((snap) async {
          bool changed = false;
          for (final change in snap.docChanges) {
            if (change.type == DocumentChangeType.removed) {
              await remove(change.doc.id);
            } else {
              await upsert(change.doc);
            }
            changed = true;
          }
          if (changed) onChanged?.call();
        }, onError: (e) => debugPrint('❌ Listener weekly_trainings (own): $e'));

    // ── Entrenamientos COMPARTIDOS CONMIGO ────────────────────────────────────
    final subShared = _firestore
        .collection(_collection)
        .where('shared_with', arrayContains: _uid)
        .snapshots()
        .listen(
          (snap) async {
            bool changed = false;
            for (final change in snap.docChanges) {
              if (change.type == DocumentChangeType.removed) {
                await remove(change.doc.id);
                // El dueño dejó de compartírmelo → limpio el "oculto" para que,
                // si me lo vuelve a compartir, reaparezca.
                await DismissedSharedService.instance.undismiss(change.doc.id);
              } else {
                await upsert(change.doc);
              }
              changed = true;
            }
            if (changed) onChanged?.call();
          },
          onError: (e) =>
              debugPrint('❌ Listener weekly_trainings (shared): $e'),
        );

    _subscriptions.addAll([subOwn, subShared]);
  }

  void stopListening() {
    for (final s in _subscriptions) s.cancel();
    _subscriptions.clear();
  }

  Future<void> _pushToFirebase(WeeklyTrainingEntry entry) async {
    if (_uid.isEmpty) return;
    try {
      final payload = <String, dynamic>{
        'date': Timestamp.fromMillisecondsSinceEpoch(entry.date),
        'training_type': entry.trainingType,
        'title': entry.title,
        'description': entry.description,
        'is_done': entry.isDone,
        'owner_id': _uid,
        'owner_name': _displayName,
        'shared_with': _jsonToList(entry.sharedWith),
        'updated_at': FieldValue.serverTimestamp(),
      };
      await _firestore
          .collection(_collection)
          .doc(entry.id)
          .set(payload, SetOptions(merge: true));
      await DBProvider.db.insertOrReplace(
        DBSchema.tableWeeklyTrainings,
        entry.copyWith(synced: 1).toMap(),
      );
    } catch (e) {
      debugPrint('❌ Error push weekly_training: $e');
    }
  }

  /// Solo empuja el flag de completado (para entrenamientos ajenos compartidos
  /// conmigo — reservado para cuando se habilite compartir con amigos).
  Future<void> _pushDoneFlagOnly(WeeklyTrainingEntry entry) async {
    if (_uid.isEmpty) return;
    try {
      await _firestore.collection(_collection).doc(entry.id).set({
        'is_done': entry.isDone,
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      await DBProvider.db.insertOrReplace(
        DBSchema.tableWeeklyTrainings,
        entry.copyWith(synced: 1).toMap(),
      );
    } catch (e) {
      debugPrint('❌ Error push is_done (entrenamiento compartido): $e');
    }
  }

  Future<void> _deleteFromFirebase(String id) async {
    if (_uid.isEmpty) return;
    try {
      await _firestore.collection(_collection).doc(id).delete();
    } catch (e) {
      debugPrint('❌ Error delete weekly_training: $e');
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
      'wtr_${_uid}_${DateTime.now().microsecondsSinceEpoch}_${_idCounter++}';

  /// Firestore (List) → JSON string para SQLite.
  String _listToJson(dynamic raw) {
    if (raw == null) return '';
    final list = raw as List<dynamic>;
    if (list.isEmpty) return '';
    return '[${list.map((e) => '"$e"').join(',')}]';
  }

  /// JSON string de SQLite → List para Firestore.
  List<String> _jsonToList(String json) {
    if (json.isEmpty) return const [];
    return RegExp(
      r'"([^"]+)"',
    ).allMatches(json).map((m) => m.group(1)!).toList();
  }
}
