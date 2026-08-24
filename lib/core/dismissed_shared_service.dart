// lib/core/dismissed_shared_service.dart
import 'db_provider.dart';
import 'db_schema.dart';

/// Gestiona los items COMPARTIDOS CONMIGO que el usuario decide ocultar
/// ("quitar") de su vista, sin borrarlos para el dueño en Firebase.
///
/// Regla de reaparición: cuando el dueño deja de compartirme un item, los
/// listeners disparan un `removed` y ahí se llama a [undismiss]. Si más tarde
/// me lo vuelve a compartir, llegará como `added` y volverá a aparecer.
class DismissedSharedService {
  DismissedSharedService._();
  static final DismissedSharedService instance = DismissedSharedService._();

  // Tipos válidos: 'menus' | 'tasks' | 'trainings'

  Future<void> dismiss(String id, String type) async {
    if (id.isEmpty) return;
    await DBProvider.db.insertOrReplace(DBSchema.tableDismissedShared, {
      'item_id': id,
      'item_type': type,
    });
  }

  Future<void> dismissAll(Iterable<String> ids, String type) async {
    final rows = ids
        .where((id) => id.isNotEmpty)
        .map((id) => {'item_id': id, 'item_type': type})
        .toList();
    if (rows.isEmpty) return;
    await DBProvider.db.batchInsert(DBSchema.tableDismissedShared, rows);
  }

  /// Quita la marca de "oculto" para [id] (en cualquier tipo). Se llama cuando
  /// el item deja de estar compartido conmigo, para permitir que reaparezca
  /// si me lo vuelven a compartir.
  Future<void> undismiss(String id) async {
    if (id.isEmpty) return;
    await DBProvider.db.delete(
      DBSchema.tableDismissedShared,
      where: 'item_id = ?',
      whereArgs: [id],
    );
  }

  /// Set de ids ocultos para un tipo concreto (para filtrar en las lecturas).
  Future<Set<String>> idsForType(String type) async {
    final rows = await DBProvider.db.query(
      DBSchema.tableDismissedShared,
      where: 'item_type = ?',
      whereArgs: [type],
    );
    return rows.map((r) => r['item_id'] as String).toSet();
  }
}
