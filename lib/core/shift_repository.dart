// lib/core/shift_repository.dart
import 'dart:math';
import 'package:flutter/material.dart';
import '../models/shift_model.dart';
import 'db_provider.dart';
import 'firebase_sync_service.dart';

class ShiftRepository {
  ShiftRepository._();
  static final ShiftRepository instance = ShiftRepository._();

  static final List<ShiftModel> _defaults = [
    ShiftModel(
      id: 'default_morning',
      name: 'MAÑANA',
      color: const Color(0xFFFF9800),
      from: const TimeOfDay(hour: 6, minute: 0),
      to: const TimeOfDay(hour: 14, minute: 0),
      sortOrder: 0,
    ),
    ShiftModel(
      id: 'default_afternoon',
      name: 'TARDE',
      color: const Color.fromARGB(255, 243, 33, 33),
      from: const TimeOfDay(hour: 14, minute: 0),
      to: const TimeOfDay(hour: 22, minute: 0),
      sortOrder: 1,
    ),
    ShiftModel(
      id: 'default_night',
      name: 'NOCHE',
      color: const Color.fromARGB(255, 39, 51, 121),
      from: const TimeOfDay(hour: 22, minute: 0),
      to: const TimeOfDay(hour: 6, minute: 0),
      sortOrder: 2,
    ),
    ShiftModel(
      id: 'default_holidays',
      name: 'VACACIONES',
      color: const Color.fromARGB(255, 63, 181, 93),
      from: const TimeOfDay(hour: 6, minute: 0),
      to: const TimeOfDay(hour: 15, minute: 0),
      sortOrder: 2,
    ),
  ];

  String _generateId() {
    final rand = Random();
    final suffix = List.generate(
      8,
      (_) => rand.nextInt(36).toRadixString(36),
    ).join();
    return '${DateTime.now().millisecondsSinceEpoch}_$suffix';
  }

  Map<String, dynamic> _toMap(ShiftModel s) => {
    'id': s.id ?? _generateId(),
    'name': s.name,
    'color': s.color.value,
    'from_minutes': s.from.hour * 60 + s.from.minute,
    'to_minutes': s.to.hour * 60 + s.to.minute,
    'euro_per_hour': s.euroPerHour,
    'sort_order': s.sortOrder,
  };

  ShiftModel _fromMap(Map<String, dynamic> m) {
    final fromMin = (m['from_minutes'] as int?) ?? 0;
    final toMin = (m['to_minutes'] as int?) ?? 0;
    final euro = m['euro_per_hour'];
    return ShiftModel(
      id: m['id'] as String?,
      name: (m['name'] as String?) ?? '',
      color: Color((m['color'] as int?) ?? Colors.blue.value),
      from: TimeOfDay(hour: fromMin ~/ 60, minute: fromMin % 60),
      to: TimeOfDay(hour: toMin ~/ 60, minute: toMin % 60),
      euroPerHour: euro != null ? (euro as num).toDouble() : null,
      sortOrder: (m['sort_order'] as int?) ?? 0,
    );
  }

  Future<void> seedDefaults() async {
    final existing = await getAll();
    if (existing.isNotEmpty) return;
    final rows = _defaults.map(_toMap).toList();
    await DBProvider.db.batchInsert('shifts', rows);
  }

  Future<List<ShiftModel>> getAll() async {
    final rows = await DBProvider.db.query(
      'shifts',
      orderBy: 'sort_order ASC, name ASC',
    );
    return rows.map(_fromMap).toList();
  }

  Future<ShiftModel> save(ShiftModel shift) async {
    final id = shift.id ?? _generateId();
    final copy = shift.copyWith(id: id);
    // SQLite
    await DBProvider.db.insertOrReplace('shifts', _toMap(copy));
    // Firebase
    await FirebaseSyncService.instance.pushShift(copy);
    return copy;
  }

  Future<void> delete(String id) async {
    await DBProvider.db.delete('shifts', where: 'id = ?', whereArgs: [id]);
    await FirebaseSyncService.instance.deleteShift(id);
  }
}
