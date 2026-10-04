// lib/core/series_id.dart
//
// Identifica las repeticiones de un mismo elemento (una "serie").
//
// Las repeticiones se guardan como copias reales (ver recurrence_rule.dart).
// Para saber cuáles pertenecen a la misma serie, cada copia lleva el id del
// ORIGINAL más un sufijo:
//
//   original ............ wt_abc_1712345678_0
//   2ª repetición ....... wt_abc_1712345678_0__r1
//   3ª repetición ....... wt_abc_1712345678_0__r2
//
// Así no hace falta ninguna columna ni campo nuevo: el id viaja igual a
// Firebase y a los amigos con los que se comparte, y la serie se reconoce
// en cualquier dispositivo. Los ids que genera la app nunca contienen "__r"
// (solo llevan guiones bajos sueltos), así que no hay confusión posible.
//
// Las series creadas antes de este cambio no llevan sufijo: para las tareas se
// reconocen por su campo `recurrence` (ver WeeklyTaskRepository.seriesIdsOf);
// en menús, entrenamientos y eventos antiguos no queda rastro de la serie y se
// borran de uno en uno, como hasta ahora.

class SeriesId {
  SeriesId._();

  static const String separator = '__r';

  /// Id de la repetición número [index] (1, 2, 3…) de la serie [rootId].
  static String copyId(String rootId, int index) => '$rootId$separator$index';

  /// Id del original de la serie a la que pertenece [id] (o el propio [id]).
  static String rootOf(String id) {
    final i = id.indexOf(separator);
    return i < 0 ? id : id.substring(0, i);
  }

  /// WHERE de SQLite que selecciona el original y todas sus repeticiones.
  /// Usa substr (no LIKE) porque '_' es un comodín en LIKE.
  static (String, List<Object>) sqlWhere(String id) {
    final root = rootOf(id);
    final prefix = '$root$separator';
    return ('(id = ? OR substr(id, 1, ?) = ?)', [root, prefix.length, prefix]);
  }
}
