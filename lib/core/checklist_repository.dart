// lib/core/checklist_repository.dart

import 'dart:math';
import '../models/checklist_item.dart';
import 'db_provider.dart';
import 'firebase_sync_service.dart';

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

  /// Guarda la lista de textos como items del evento en SQLite y en Firestore
  /// (embebidos dentro del documento del evento para sincronización fiable).
  Future<void> saveAll(String eventId, List<String> texts) async {
    // Borrar items anteriores solo en SQLite
    // (Firestore se actualiza con el mapa completo a continuación)
    await DBProvider.db.delete(
      _table,
      where: 'event_id = ?',
      whereArgs: [eventId],
    );

    final rows = texts.asMap().entries.map((e) {
      return {
        'id': _generateId(),
        'event_id': eventId,
        'text': e.value,
        'is_checked': 0,
        'position': e.key,
      };
    }).toList();

    if (rows.isNotEmpty) {
      // 1. SQLite local
      await DBProvider.db.batchInsert(_table, rows);

      // 2. Firestore: embebidos en el doc del evento
      //    Sin race condition ni índice extra necesario
      await FirebaseSyncService.instance.pushChecklistToEvent(eventId, rows);
    }
  }

  /// Marca/desmarca un item tanto en SQLite como en Firestore.
  /// Requiere el eventId para actualizar el campo correcto en el doc del evento.
  Future<void> updateChecked(
    String itemId,
    String eventId,
    bool isChecked,
  ) async {
    // 1. SQLite local
    final db = await DBProvider.db.database;
    await db.update(
      _table,
      {'is_checked': isChecked ? 1 : 0},
      where: 'id = ?',
      whereArgs: [itemId],
    );

    // 2. Firestore: actualiza solo el campo is_checked del item en el evento
    await FirebaseSyncService.instance.pushChecklistItemChecked(
      eventId,
      itemId,
      isChecked,
    );
  }

  /// Elimina todos los items de un evento.
  Future<void> deleteAllForEvent(String eventId) async {
    await DBProvider.db.delete(
      _table,
      where: 'event_id = ?',
      whereArgs: [eventId],
    );
    // En Firestore borramos el campo checklist_items del evento
    // (no hay colección separada que limpiar)
    try {
      await FirebaseSyncService.instance.pushChecklistToEvent(eventId, []);
    } catch (_) {}
  }

  /// Elimina un item concreto localmente.
  Future<void> deleteItem(String itemId) async {
    await DBProvider.db.delete(_table, where: 'id = ?', whereArgs: [itemId]);
  }
}
