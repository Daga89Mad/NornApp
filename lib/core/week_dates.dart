// lib/core/week_dates.dart
//
// Aritmética de fechas SEGURA frente al cambio de hora (DST).
//
// Nunca uses Duration(days: n) sobre un DateTime local para moverte por el
// calendario: Duration suma tiempo absoluto (7 días = 168 horas exactas), y el
// día del cambio de hora tiene 23 o 25 horas. Al cruzarlo, el resultado se
// desplaza una hora y deja de caer a medianoche:
//
//   Lun 19 oct 00:00 CEST + Duration(days: 7) = Dom 25 oct 23:00 CET
//
// El constructor DateTime(y, m, d + n) normaliza por calendario y siempre
// devuelve medianoche local, que es lo que necesitan las pantallas semanales.

/// Medianoche local del día de [d].
DateTime startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

/// [d] más [n] días de calendario ([n] puede ser negativo), a medianoche.
DateTime addDays(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);

/// Lunes (medianoche) de la semana a la que pertenece [d].
DateTime mondayOf(DateTime d) =>
    DateTime(d.year, d.month, d.day - (d.weekday - 1));

/// Último milisegundo del domingo de la semana que empieza en [monday].
int endOfWeekMs(DateTime monday) =>
    DateTime(monday.year, monday.month, monday.day + 7).millisecondsSinceEpoch -
    1;

/// Último milisegundo del día [d].
int endOfDayMs(DateTime d) =>
    DateTime(d.year, d.month, d.day + 1).millisecondsSinceEpoch - 1;

/// Días de calendario entre [from] y [to], ignorando horas y DST.
/// (difference().inDays devolvería 6 en una semana con cambio de hora.)
int daysBetween(DateTime from, DateTime to) {
  final a = startOfDay(from);
  final b = startOfDay(to);
  return (b.difference(a).inHours / 24).round();
}

/// True si [a] y [b] son el mismo día natural.
bool isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
