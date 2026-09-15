// lib/core/shared_date_override_service.dart
import 'db_provider.dart';
import 'db_schema.dart';

/// Fecha LOCAL en la que yo veo un item que no es mío.
///
/// Cuando muevo de día una tarea / menú / entrenamiento que me han compartido,
/// el cambio se aplica aquí al instante (yo lo veo ya en el día nuevo) y a la
/// vez se envía una propuesta al dueño y al resto de destinatarios
/// (ver [DateChangeService]).
///
/// Si esa propuesta se acepta, el dueño cambia la fecha real del documento y
/// entonces este override deja de hacer falta: se borra solo en la siguiente
/// lectura (ver [reconcile]).
///
/// Tipos válidos: 'menus' | 'tasks' | 'trainings'
class SharedDateOverrideService {
  SharedDateOverrideService._();
  static final SharedDateOverrideService instance =
      SharedDateOverrideService._();

  /// Fija (o actualiza) el día local para [id]. [dateMs] normalizado a medianoche.
  Future<void> setOverride(String id, String type, int dateMs) async {
    if (id.isEmpty) return;
    await DBProvider.db.insertOrReplace(DBSchema.tableSharedDateOverrides, {
      'item_id': id,
      'item_type': type,
      'date': dateMs,
    });
  }

  Future<void> setOverrideDay(String id, String type, DateTime day) async {
    await setOverride(
      id,
      type,
      DateTime(day.year, day.month, day.day).millisecondsSinceEpoch,
    );
  }

  /// Elimina el override: el item vuelve al día real del documento.
  Future<void> clear(String id, String type) async {
    if (id.isEmpty) return;
    await DBProvider.db.delete(
      DBSchema.tableSharedDateOverrides,
      where: 'item_id = ? AND item_type = ?',
      whereArgs: [id, type],
    );
  }

  /// Quita el override en cualquier tipo (p. ej. si dejan de compartírmelo).
  Future<void> clearAnyType(String id) async {
    if (id.isEmpty) return;
    await DBProvider.db.delete(
      DBSchema.tableSharedDateOverrides,
      where: 'item_id = ?',
      whereArgs: [id],
    );
  }

  /// Mapa { item_id : dateMs } de todos los overrides de un tipo.
  Future<Map<String, int>> mapForType(String type) async {
    final rows = await DBProvider.db.query(
      DBSchema.tableSharedDateOverrides,
      where: 'item_type = ?',
      whereArgs: [type],
    );
    return {for (final r in rows) (r['item_id'] as String): (r['date'] as int)};
  }

  Future<int?> dateFor(String id, String type) async {
    final rows = await DBProvider.db.query(
      DBSchema.tableSharedDateOverrides,
      where: 'item_id = ? AND item_type = ?',
      whereArgs: [id, type],
      limit: '1',
    );
    if (rows.isEmpty) return null;
    return rows.first['date'] as int;
  }

  /// Limpia los overrides que ya no aportan nada porque la fecha real del
  /// documento coincide con ellos (la propuesta fue aceptada por el dueño).
  ///
  /// [realDates] es { item_id : date real leída de la tabla }.
  Future<void> reconcile(String type, Map<String, int> realDates) async {
    final current = await mapForType(type);
    for (final entry in current.entries) {
      final real = realDates[entry.key];
      if (real != null && real == entry.value) {
        await clear(entry.key, type);
      }
    }
  }

  /// Construye el fragmento SQL para incluir también los items MOVIDOS a este
  /// rango aunque su fecha original esté fuera de él.
  /// Devuelve (whereSql, args) listos para DBProvider.query.
  static (String, List<dynamic>) buildRangeWhere({
    required int fromMs,
    required int toMs,
    required Map<String, int> overrides,
    String dateColumn = 'date',
    String idColumn = 'id',
  }) {
    final movedIn = overrides.entries
        .where((e) => e.value >= fromMs && e.value <= toMs)
        .map((e) => e.key)
        .toList();

    final base = '($dateColumn >= ? AND $dateColumn <= ?)';
    final args = <dynamic>[fromMs, toMs];

    if (movedIn.isEmpty) return (base, args);

    final placeholders = List.filled(movedIn.length, '?').join(',');
    args.addAll(movedIn);
    return ('($base OR $idColumn IN ($placeholders))', args);
  }
}
