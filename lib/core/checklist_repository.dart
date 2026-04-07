// lib/core/checklist_repository.dart

import 'dart:math';
import '../models/checklist_item.dart';
import 'db_provider.dart';

class ChecklistRepository {
  ChecklistRepository._();
  static final ChecklistRepository instance = ChecklistRepository._();

  static const String _table = 'checklist_items';

  String _generateId() {
    final rand = Random();
    final suffix = List.generate(
      8,
      (_) => rand.nextInt(36).toRadixString(36),
    ).join();
    return '${DateTime.now().millisecondsSinceEpoch}_$suffix';
  }

  Map<String, dynamic> _toMap(ChecklistItem item) => {
    'id': item.id ?? _generateId(),
    'event_id': item.eventId,
    'text': item.text,
    'is_checked': item.isChecked ? 1 : 0,
    'position': item.position,
  };

  ChecklistItem _fromMap(Map<String, dynamic> m) => ChecklistItem(
    id: m['id'] as String?,
    eventId: m['event_id'] as String,
    text: m['text'] as String,
    isChecked: (m['is_checked'] as int) == 1,
    position: (m['position'] as int?) ?? 0,
  );

  // ── Queries ────────────────────────────────────────────────────────────────

  Future<List<ChecklistItem>> getItemsForEvent(String eventId) async {
    final rows = await DBProvider.db.query(
      _table,
      where: 'event_id = ?',
      whereArgs: [eventId],
      orderBy: 'position ASC',
    );
    return rows.map(_fromMap).toList();
  }

  // ── Escritura ──────────────────────────────────────────────────────────────

  /// Guarda una lista de textos como items de un evento.
  /// Borra los anteriores y los reinserta en orden.
  Future<void> saveAll(String eventId, List<String> texts) async {
    await deleteAllForEvent(eventId);
    final rows = texts.asMap().entries.map((e) {
      final id = _generateId();
      return {
        'id': id,
        'event_id': eventId,
        'text': e.value,
        'is_checked': 0,
        'position': e.key,
      };
    }).toList();
    if (rows.isNotEmpty) {
      await DBProvider.db.batchInsert(_table, rows);
    }
  }

  /// Cambia el estado checked de un item.
  Future<void> updateChecked(String itemId, bool isChecked) async {
    final db = await DBProvider.db.database;
    await db.update(
      _table,
      {'is_checked': isChecked ? 1 : 0},
      where: 'id = ?',
      whereArgs: [itemId],
    );
  }

  /// Elimina todos los items de un evento (útil al borrar el evento).
  Future<void> deleteAllForEvent(String eventId) async {
    await DBProvider.db.delete(
      _table,
      where: 'event_id = ?',
      whereArgs: [eventId],
    );
  }

  /// Elimina un item concreto.
  Future<void> deleteItem(String itemId) async {
    await DBProvider.db.delete(_table, where: 'id = ?', whereArgs: [itemId]);
  }
}
