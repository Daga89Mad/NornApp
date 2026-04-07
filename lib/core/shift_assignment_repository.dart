// lib/core/shift_assignment_repository.dart
import 'dart:math';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../models/shift_model.dart';
import 'db_provider.dart';
import 'db_schema.dart';
import 'shift_repository.dart';
import 'firebase_sync_service.dart';

class ShiftAssignmentRepository {
  ShiftAssignmentRepository._();
  static final ShiftAssignmentRepository instance =
      ShiftAssignmentRepository._();

  static const String _table = 'shift_assignments';

  String _generateId() {
    final rand = Random();
    final suffix = List.generate(
      8,
      (_) => rand.nextInt(36).toRadixString(36),
    ).join();
    return '${DateTime.now().millisecondsSinceEpoch}_$suffix';
  }

  int _dayMs(DateTime d) =>
      DateTime.utc(d.year, d.month, d.day).millisecondsSinceEpoch;

  String? get _myUid => FirebaseAuth.instance.currentUser?.uid;

  // ── Consultas ──────────────────────────────────────────────────────────────

  Future<List<ShiftModel>> getShiftsForDay(DateTime day) async {
    final rows = await DBProvider.db.query(
      _table,
      where: 'date = ?',
      whereArgs: [_dayMs(day)],
    );
    if (rows.isEmpty) return [];
    final allShifts = await ShiftRepository.instance.getAll();
    final shiftMap = {for (final s in allShifts) s.id: s};
    return rows
        .where((r) => (r['owner_id'] == null || r['owner_id'] == _myUid))
        .map((r) => shiftMap[r['shift_id'] as String])
        .whereType<ShiftModel>()
        .toList();
  }

  Future<Map<DateTime, List<ShiftModel>>> getShiftsForMonth(
    int year,
    int month,
  ) async {
    final firstMs = DateTime.utc(year, month, 1).millisecondsSinceEpoch;
    final lastMs = DateTime.utc(year, month + 1, 1).millisecondsSinceEpoch - 1;
    final rows = await DBProvider.db.query(
      _table,
      where: 'date >= ? AND date <= ?',
      whereArgs: [firstMs, lastMs],
    );
    if (rows.isEmpty) return {};
    final allShifts = await ShiftRepository.instance.getAll();
    final shiftMap = {for (final s in allShifts) s.id: s};
    final Map<DateTime, List<ShiftModel>> result = {};
    for (final row in rows) {
      if (row['owner_id'] != null && row['owner_id'] != _myUid) continue;
      final key = DateTime.fromMillisecondsSinceEpoch(
        row['date'] as int,
        isUtc: true,
      );
      final shift = shiftMap[row['shift_id'] as String];
      if (shift != null) result.putIfAbsent(key, () => []).add(shift);
    }
    return result;
  }

  Future<Set<String>> getAssignedShiftIds(DateTime day) async {
    final rows = await DBProvider.db.query(
      _table,
      where: 'date = ?',
      whereArgs: [_dayMs(day)],
    );
    return rows
        .where((r) => r['owner_id'] == null || r['owner_id'] == _myUid)
        .map((r) => r['shift_id'] as String)
        .toSet();
  }

  // ── Turnos compartidos de amigos ───────────────────────────────────────────

  /// Devuelve los turnos de amigos para el día (owner_id != myUid).
  /// Incluye toda la info necesaria para mostrarlos en el timeline.
  Future<List<SharedShiftInfo>> getSharedShiftsForDay(DateTime day) async {
    final uid = _myUid;
    if (uid == null) return [];
    final rows = await DBProvider.db.query(
      _table,
      where: 'date = ? AND owner_id IS NOT NULL AND owner_id != ?',
      whereArgs: [_dayMs(day), uid],
    );
    return rows
        .map(
          (r) => SharedShiftInfo(
            shiftId: r['shift_id'] as String,
            ownerUid: r['owner_id'] as String,
            name: (r['shift_name'] as String?) ?? '',
            color: Color((r['shift_color'] as int?) ?? 0xFF2196F3),
            fromMinutes: (r['shift_from_minutes'] as int?) ?? 0,
            toMinutes: (r['shift_to_minutes'] as int?) ?? 0,
          ),
        )
        .toList();
  }

  /// Devuelve los turnos compartidos de amigos para todo el mes.
  Future<Map<DateTime, List<SharedShiftInfo>>> getSharedShiftsForMonth(
    int year,
    int month,
  ) async {
    final uid = _myUid;
    if (uid == null) return {};

    final firstMs = DateTime.utc(year, month, 1).millisecondsSinceEpoch;
    final lastMs = DateTime.utc(year, month + 1, 1).millisecondsSinceEpoch - 1;

    final rows = await DBProvider.db.query(
      _table,
      where:
          'date >= ? AND date <= ? AND owner_id IS NOT NULL AND owner_id != ?',
      whereArgs: [firstMs, lastMs, uid],
    );

    final Map<DateTime, List<SharedShiftInfo>> result = {};
    for (final r in rows) {
      final key = DateTime.fromMillisecondsSinceEpoch(
        r['date'] as int,
        isUtc: true,
      );
      result
          .putIfAbsent(key, () => [])
          .add(
            SharedShiftInfo(
              shiftId: r['shift_id'] as String,
              ownerUid: r['owner_id'] as String,
              name: (r['shift_name'] as String?) ?? '',
              color: Color((r['shift_color'] as int?) ?? 0xFF2196F3),
              fromMinutes: (r['shift_from_minutes'] as int?) ?? 0,
              toMinutes: (r['shift_to_minutes'] as int?) ?? 0,
            ),
          );
    }
    return result;
  }

  // ── Toggle ─────────────────────────────────────────────────────────────────

  Future<bool> toggle(String shiftId, DateTime day) async {
    final uid = _myUid;
    final assigned = await getAssignedShiftIds(day);
    if (assigned.contains(shiftId)) {
      await DBProvider.db.delete(
        _table,
        where: 'shift_id = ? AND date = ?',
        whereArgs: [shiftId, _dayMs(day)],
      );
      await FirebaseSyncService.instance.deleteShiftAssignment(shiftId, day);
      return false;
    } else {
      final id = _generateId();
      // Obtener datos del turno para desnormalizar
      final allShifts = await ShiftRepository.instance.getAll();
      final shift = allShifts.firstWhere(
        (s) => s.id == shiftId,
        orElse: () => ShiftModel(
          name: '',
          color: Colors.blue,
          from: const TimeOfDay(hour: 0, minute: 0),
          to: const TimeOfDay(hour: 8, minute: 0),
        ),
      );
      final fromMin = shift.from.hour * 60 + shift.from.minute;
      final toMin = shift.to.hour * 60 + shift.to.minute;

      await DBProvider.db.insertOrReplace(_table, {
        'id': id,
        'shift_id': shiftId,
        'date': _dayMs(day),
        'owner_id': uid,
        'shift_name': shift.name,
        'shift_color': shift.color.value,
        'shift_from_minutes': fromMin,
        'shift_to_minutes': toMin,
      });
      await FirebaseSyncService.instance.pushShiftAssignment(
        id,
        shiftId,
        day,
        shift: shift,
      );
      return true;
    }
  }

  Future<void> deleteAllForShift(String shiftId) async {
    await DBProvider.db.delete(
      _table,
      where: 'shift_id = ?',
      whereArgs: [shiftId],
    );
  }
}

// ── Modelo para turno compartido ──────────────────────────────────────────────

class SharedShiftInfo {
  final String shiftId;
  final String ownerUid;
  final String name;
  final Color color;
  final int fromMinutes;
  final int toMinutes;

  const SharedShiftInfo({
    required this.shiftId,
    required this.ownerUid,
    required this.name,
    required this.color,
    required this.fromMinutes,
    required this.toMinutes,
  });

  TimeOfDay get from =>
      TimeOfDay(hour: fromMinutes ~/ 60, minute: fromMinutes % 60);
  TimeOfDay get to => TimeOfDay(hour: toMinutes ~/ 60, minute: toMinutes % 60);
}
