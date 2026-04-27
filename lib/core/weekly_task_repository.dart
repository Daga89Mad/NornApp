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
    final sharedUids = await WeeklyShareService.instance.getSharedUidsForType(
      'tasks',
    );
    final sharedJson = sharedUids.isEmpty
        ? ''
        : '[${sharedUids.map((u) => '"$u"').join(',')}]';

    final toSave = task.copyWith(
      ownerId: _uid,
      ownerName: _displayName,
      sharedWith: task.ownerId == _uid || task.ownerId.isEmpty
          ? sharedJson
          : task.sharedWith,
      synced: 0,
    );
    await DBProvider.db.insertOrReplace(
      DBSchema.tableWeeklyTasks,
      toSave.toMap(),
    );
    _pushToFirebase(toSave, sharedUids);
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
      if (sharedUids.isNotEmpty) {
        payload['shared_with'] = sharedUids;
      }
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
}
