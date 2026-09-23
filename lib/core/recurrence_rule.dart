// lib/core/recurrence_rule.dart
//
// Regla de repetición común para tareas, menús, entrenamientos y eventos del
// calendario.
//
// La app MATERIALIZA las repeticiones: al guardar se crea una copia real por
// cada fecha (como ya hacían las tareas). Así cada repetición se puede marcar,
// mover, compartir o borrar por separado y no hace falta tocar las consultas.
//
// Frecuencias:
//   none        → no se repite
//   daily       → cada día
//   weekly      → cada semana
//   biweekly    → cada dos semanas
//   monthly     → cada mes (mismo día; los meses sin ese día se saltan)
//   everyNDays  → cada X días
//
// Todas llevan un "hasta" (fecha final incluida). El "desde" es la fecha del
// propio elemento. Las fechas se calculan con aritmética de calendario
// (week_dates.dart), nunca con Duration, para no desplazarse con el cambio
// de hora.
//
// Codificación (columna `recurrence` de weekly_tasks y Firestore):
//   'none' | 'daily' | 'weekly' | 'biweekly' | 'monthly' | 'every:N'
//   + opcional '|until:AAAAMMDD'
// Compatible con los valores antiguos 'none' / 'daily' / 'weekly'.

import 'week_dates.dart';

enum RecurrenceFreq { none, daily, weekly, biweekly, monthly, everyNDays }

class RecurrenceRule {
  final RecurrenceFreq freq;

  /// Solo se usa con [RecurrenceFreq.everyNDays] (mínimo 1).
  final int interval;

  /// Última fecha (incluida). Si es null se usa [defaultUntil].
  final DateTime? until;

  const RecurrenceRule({
    this.freq = RecurrenceFreq.none,
    this.interval = 2,
    this.until,
  });

  static const RecurrenceRule none = RecurrenceRule();

  /// Límite de seguridad: evita crear miles de documentos por error.
  static const int maxOccurrences = 366;

  bool get isNone => freq == RecurrenceFreq.none;

  RecurrenceRule copyWith({
    RecurrenceFreq? freq,
    int? interval,
    DateTime? until,
    bool clearUntil = false,
  }) => RecurrenceRule(
    freq: freq ?? this.freq,
    interval: interval ?? this.interval,
    until: clearUntil ? null : (until ?? this.until),
  );

  // ══════════════════════════════════════════════════════════════════════════
  // FECHAS
  // ══════════════════════════════════════════════════════════════════════════

  /// Fecha final sugerida según la frecuencia.
  DateTime defaultUntil(DateTime start) {
    final s = startOfDay(start);
    switch (freq) {
      case RecurrenceFreq.none:
        return s;
      case RecurrenceFreq.daily:
        return addDays(s, 29); // 30 días
      case RecurrenceFreq.weekly:
        return addDays(s, 7 * 11); // 12 semanas
      case RecurrenceFreq.biweekly:
        return addDays(s, 14 * 11); // 12 repeticiones
      case RecurrenceFreq.monthly:
        return DateTime(s.year + 1, s.month, s.day); // 1 año
      case RecurrenceFreq.everyNDays:
        return DateTime(s.year, s.month + 3, s.day); // 3 meses
    }
  }

  int get _stepDays {
    switch (freq) {
      case RecurrenceFreq.daily:
        return 1;
      case RecurrenceFreq.weekly:
        return 7;
      case RecurrenceFreq.biweekly:
        return 14;
      case RecurrenceFreq.everyNDays:
        return interval < 1 ? 1 : interval;
      case RecurrenceFreq.none:
      case RecurrenceFreq.monthly:
        return 0;
    }
  }

  /// Todas las fechas (medianoche local) desde [start] hasta [until],
  /// incluida la propia [start]. Con [isNone] devuelve solo [start].
  List<DateTime> occurrences(DateTime start) {
    final s = startOfDay(start);
    if (isNone) return [s];

    var end = startOfDay(until ?? defaultUntil(s));
    if (end.isBefore(s)) end = s;

    final out = <DateTime>[];
    for (var i = 0; out.length < maxOccurrences; i++) {
      final DateTime d;
      if (freq == RecurrenceFreq.monthly) {
        d = DateTime(s.year, s.month + i, s.day);
        if (d.isAfter(end)) break;
        // Mes sin ese día (31, 30, 29-feb): Dart lo pasa al mes siguiente.
        if (d.day != s.day) continue;
      } else {
        d = addDays(s, _stepDays * i);
        if (d.isAfter(end)) break;
      }
      out.add(d);
    }
    return out;
  }

  /// true si se alcanzó el límite [maxOccurrences] antes de la fecha final.
  bool isTruncated(DateTime start) {
    final list = occurrences(start);
    if (list.length < maxOccurrences) return false;
    final end = startOfDay(until ?? defaultUntil(start));
    return list.last.isBefore(end);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // TEXTO
  // ══════════════════════════════════════════════════════════════════════════

  static const _meses = [
    '',
    'ene',
    'feb',
    'mar',
    'abr',
    'may',
    'jun',
    'jul',
    'ago',
    'sep',
    'oct',
    'nov',
    'dic',
  ];

  static String fmtDate(DateTime d) => '${d.day} ${_meses[d.month]} ${d.year}';

  String get freqLabel {
    switch (freq) {
      case RecurrenceFreq.none:
        return 'No repetir';
      case RecurrenceFreq.daily:
        return 'Cada día';
      case RecurrenceFreq.weekly:
        return 'Cada semana';
      case RecurrenceFreq.biweekly:
        return 'Cada 2 semanas';
      case RecurrenceFreq.monthly:
        return 'Cada mes';
      case RecurrenceFreq.everyNDays:
        return interval == 1 ? 'Cada día' : 'Cada $interval días';
    }
  }

  String describe(DateTime start) {
    if (isNone) return 'No se repite';
    final end = until ?? defaultUntil(start);
    return '$freqLabel · hasta el ${fmtDate(end)}';
  }

  // ══════════════════════════════════════════════════════════════════════════
  // SERIALIZACIÓN
  // ══════════════════════════════════════════════════════════════════════════

  String encode() {
    if (isNone) return 'none';
    final String base;
    switch (freq) {
      case RecurrenceFreq.daily:
        base = 'daily';
        break;
      case RecurrenceFreq.weekly:
        base = 'weekly';
        break;
      case RecurrenceFreq.biweekly:
        base = 'biweekly';
        break;
      case RecurrenceFreq.monthly:
        base = 'monthly';
        break;
      case RecurrenceFreq.everyNDays:
        base = 'every:$interval';
        break;
      case RecurrenceFreq.none:
        base = 'none';
        break;
    }
    if (until == null) return base;
    final u = until!;
    final ymd =
        '${u.year.toString().padLeft(4, '0')}'
        '${u.month.toString().padLeft(2, '0')}'
        '${u.day.toString().padLeft(2, '0')}';
    return '$base|until:$ymd';
  }

  static RecurrenceRule decode(String? raw) {
    if (raw == null || raw.isEmpty || raw == 'none') return none;
    final parts = raw.split('|');
    final head = parts.first;

    DateTime? until;
    for (final p in parts.skip(1)) {
      if (p.startsWith('until:') && p.length >= 14) {
        final v = p.substring(6);
        final y = int.tryParse(v.substring(0, 4));
        final m = int.tryParse(v.substring(4, 6));
        final d = int.tryParse(v.substring(6, 8));
        if (y != null && m != null && d != null) until = DateTime(y, m, d);
      }
    }

    if (head == 'daily') {
      return RecurrenceRule(freq: RecurrenceFreq.daily, until: until);
    }
    if (head == 'weekly') {
      return RecurrenceRule(freq: RecurrenceFreq.weekly, until: until);
    }
    if (head == 'biweekly') {
      return RecurrenceRule(freq: RecurrenceFreq.biweekly, until: until);
    }
    if (head == 'monthly') {
      return RecurrenceRule(freq: RecurrenceFreq.monthly, until: until);
    }
    if (head.startsWith('every:')) {
      final n = int.tryParse(head.substring(6)) ?? 2;
      return RecurrenceRule(
        freq: RecurrenceFreq.everyNDays,
        interval: n < 1 ? 1 : n,
        until: until,
      );
    }
    return none;
  }
}
