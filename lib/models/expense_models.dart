// lib/models/expense_models.dart
//
// Modelos del módulo de GASTOS.
//
// Firestore:
//   expense_projects/{projectId}
//       · Un proyecto de gastos concreto (un viaje, el mes de octubre…).
//       · Si pertenece a una serie periódica, su id es '{seriesId}_{n}', lo que
//         hace imposible crear dos veces el mismo periodo aunque dos miembros
//         abran la app a la vez.
//       · Lleva totales agregados (total_cents, totals_by_uid, expense_count)
//         para pintar el listado sin leer todos los gastos.
//   expense_projects/{projectId}/expenses/{expenseId}
//       · Cada gasto introducido.
//   expense_series/{seriesId}
//       · Plantilla de un proyecto periódico: con qué parámetros se crea cada
//         periodo y cuál es el siguiente a crear (next_index).
//
// Los importes se guardan en CÉNTIMOS (int) para no arrastrar errores de
// coma flotante al sumar.

import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';

// ════════════════════════════════════════════════════════════════════════════
// ENUMS
// ════════════════════════════════════════════════════════════════════════════

/// sum      → se van sumando gastos; al final cada uno ve cuánto ha puesto.
/// subtract → se fija un total (presupuesto) y cada gasto lo va restando.
enum ExpenseProjectType { sum, subtract }

extension ExpenseProjectTypeX on ExpenseProjectType {
  String get key => this == ExpenseProjectType.sum ? 'sum' : 'subtract';

  String get label =>
      this == ExpenseProjectType.sum ? 'Sumar gastos' : 'Restar de un total';

  String get shortLabel =>
      this == ExpenseProjectType.sum ? 'Suma' : 'Presupuesto';

  static ExpenseProjectType fromKey(String? k) =>
      k == 'subtract' ? ExpenseProjectType.subtract : ExpenseProjectType.sum;
}

enum ExpenseRecurrence { once, weekly, biweekly, monthly, yearly }

extension ExpenseRecurrenceX on ExpenseRecurrence {
  String get key {
    switch (this) {
      case ExpenseRecurrence.once:
        return 'once';
      case ExpenseRecurrence.weekly:
        return 'weekly';
      case ExpenseRecurrence.biweekly:
        return 'biweekly';
      case ExpenseRecurrence.monthly:
        return 'monthly';
      case ExpenseRecurrence.yearly:
        return 'yearly';
    }
  }

  String get label {
    switch (this) {
      case ExpenseRecurrence.once:
        return 'Una sola vez';
      case ExpenseRecurrence.weekly:
        return 'Cada semana';
      case ExpenseRecurrence.biweekly:
        return 'Cada 15 días';
      case ExpenseRecurrence.monthly:
        return 'Cada mes';
      case ExpenseRecurrence.yearly:
        return 'Cada año';
    }
  }

  bool get isRecurring => this != ExpenseRecurrence.once;

  static ExpenseRecurrence fromKey(String? k) {
    switch (k) {
      case 'weekly':
        return ExpenseRecurrence.weekly;
      case 'biweekly':
        return ExpenseRecurrence.biweekly;
      case 'monthly':
        return ExpenseRecurrence.monthly;
      case 'yearly':
        return ExpenseRecurrence.yearly;
      default:
        return ExpenseRecurrence.once;
    }
  }
}

/// Días de "Cada 15 días". Si lo prefieres quincenal exacto (2 semanas),
/// cámbialo a 14.
const int kBiweeklyDays = 15;

enum ExpenseProjectStatus { upcoming, active, finished }

// ════════════════════════════════════════════════════════════════════════════
// FECHAS DE LOS PERIODOS
// ════════════════════════════════════════════════════════════════════════════

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// Suma [months] meses a [d] ajustando el día al último del mes si no existe
/// (31 ene + 1 mes = 28/29 feb). Siempre se calcula desde el ancla para que el
/// día no vaya "encogiendo" mes a mes.
DateTime addMonthsClamped(DateTime d, int months) {
  final total = d.month - 1 + months;
  final y = d.year + (total ~/ 12);
  final m = (total % 12) + 1;
  final lastDay = DateTime(y, m + 1, 0).day;
  return DateTime(y, m, math.min(d.day, lastDay));
}

/// Inicio del periodo número [n] (0 = el primero) de una serie que empieza en
/// [anchor]. Aritmética de calendario (segura frente al cambio de hora).
DateTime occurrenceStart(DateTime anchor, ExpenseRecurrence r, int n) {
  final a = _day(anchor);
  switch (r) {
    case ExpenseRecurrence.once:
      return a;
    case ExpenseRecurrence.weekly:
      return DateTime(a.year, a.month, a.day + 7 * n);
    case ExpenseRecurrence.biweekly:
      return DateTime(a.year, a.month, a.day + kBiweeklyDays * n);
    case ExpenseRecurrence.monthly:
      return addMonthsClamped(a, n);
    case ExpenseRecurrence.yearly:
      return addMonthsClamped(a, 12 * n);
  }
}

/// Fin del periodo [n].
/// · fullPeriod = true  → justo el día antes de que empiece el siguiente
///   (p. ej. mensual del 1 al último día de cada mes, tenga 28, 30 o 31).
/// · fullPeriod = false → inicio + [durationDays] (p. ej. un viaje de 5 días
///   cada año).
DateTime occurrenceEnd(
  DateTime anchor,
  ExpenseRecurrence r,
  int n, {
  required bool fullPeriod,
  required int durationDays,
}) {
  final start = occurrenceStart(anchor, r, n);
  if (r == ExpenseRecurrence.once) {
    return DateTime(start.year, start.month, start.day + durationDays);
  }
  final next = occurrenceStart(anchor, r, n + 1);
  final lastOfPeriod = DateTime(next.year, next.month, next.day - 1);
  if (fullPeriod) return lastOfPeriod;
  return DateTime(start.year, start.month, start.day + durationDays);
}

// ════════════════════════════════════════════════════════════════════════════
// DINERO
// ════════════════════════════════════════════════════════════════════════════

/// 123456 → "1.234,56 €"
String formatEuros(int cents, {bool symbol = true}) {
  final neg = cents < 0;
  final abs = cents.abs();
  final euros = (abs ~/ 100).toString();
  final dec = (abs % 100).toString().padLeft(2, '0');
  final buf = StringBuffer();
  for (var i = 0; i < euros.length; i++) {
    if (i > 0 && (euros.length - i) % 3 == 0) buf.write('.');
    buf.write(euros[i]);
  }
  return '${neg ? '-' : ''}$buf,$dec${symbol ? ' €' : ''}';
}

/// "12,50" / "12.50" / "1.234,5" / "12 €" → céntimos. null si no es válido.
int? parseEurosToCents(String input) {
  var t = input.trim().replaceAll('€', '').replaceAll(' ', '');
  if (t.isEmpty) return null;
  final lastComma = t.lastIndexOf(',');
  final lastDot = t.lastIndexOf('.');
  if (lastComma >= 0 && lastDot >= 0) {
    // El separador que aparece el último es el decimal.
    t = lastComma > lastDot
        ? t.replaceAll('.', '').replaceAll(',', '.')
        : t.replaceAll(',', '');
  } else if (lastComma >= 0) {
    t = t.replaceAll(',', '.');
  }
  final v = double.tryParse(t);
  if (v == null || v.isNaN || v.isInfinite) return null;
  return (v * 100).round();
}

// ════════════════════════════════════════════════════════════════════════════
// GASTO INICIAL (plantilla)
// ════════════════════════════════════════════════════════════════════════════

/// Gasto que se crea automáticamente al crear el proyecto (y, si es
/// periódico, en cada nuevo periodo: alquiler, cuotas, etc.).
class InitialExpense {
  final String concept;
  final int amountCents;

  const InitialExpense({required this.concept, required this.amountCents});

  Map<String, dynamic> toMap() => {
    'concept': concept,
    'amount_cents': amountCents,
  };

  factory InitialExpense.fromMap(Map<String, dynamic> m) => InitialExpense(
    concept: (m['concept'] as String?) ?? '',
    amountCents: (m['amount_cents'] as num?)?.toInt() ?? 0,
  );
}

// ════════════════════════════════════════════════════════════════════════════
// PROYECTO
// ════════════════════════════════════════════════════════════════════════════

class ExpenseProject {
  final String id;
  final String seriesId; // '' si es de una sola vez
  final int occurrenceIndex;
  final String title;
  final String description;
  final ExpenseProjectType type;
  final int budgetCents; // solo para subtract
  final DateTime startDate;
  final DateTime endDate;
  final ExpenseRecurrence recurrence;
  final String ownerId;
  final String ownerName;
  final List<String> members; // incluye al dueño
  final Map<String, String> memberNames;
  final int totalCents;
  final Map<String, int> totalsByUid;
  final int expenseCount;

  const ExpenseProject({
    required this.id,
    this.seriesId = '',
    this.occurrenceIndex = 0,
    required this.title,
    this.description = '',
    required this.type,
    this.budgetCents = 0,
    required this.startDate,
    required this.endDate,
    this.recurrence = ExpenseRecurrence.once,
    required this.ownerId,
    this.ownerName = '',
    this.members = const [],
    this.memberNames = const {},
    this.totalCents = 0,
    this.totalsByUid = const {},
    this.expenseCount = 0,
  });

  factory ExpenseProject.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    DateTime ts(dynamic v) => v is Timestamp
        ? _day(v.toDate())
        : (v is int
              ? _day(DateTime.fromMillisecondsSinceEpoch(v))
              : _day(DateTime.now()));
    return ExpenseProject(
      id: doc.id,
      seriesId: (d['series_id'] as String?) ?? '',
      occurrenceIndex: (d['occurrence_index'] as num?)?.toInt() ?? 0,
      title: (d['title'] as String?) ?? '',
      description: (d['description'] as String?) ?? '',
      type: ExpenseProjectTypeX.fromKey(d['type'] as String?),
      budgetCents: (d['budget_cents'] as num?)?.toInt() ?? 0,
      startDate: ts(d['start_date']),
      endDate: ts(d['end_date']),
      recurrence: ExpenseRecurrenceX.fromKey(d['recurrence'] as String?),
      ownerId: (d['owner_id'] as String?) ?? '',
      ownerName: (d['owner_name'] as String?) ?? '',
      members: List<String>.from(d['members'] ?? const []),
      memberNames: _stringMap(d['member_names']),
      totalCents: (d['total_cents'] as num?)?.toInt() ?? 0,
      totalsByUid: _intMap(d['totals_by_uid']),
      expenseCount: (d['expense_count'] as num?)?.toInt() ?? 0,
    );
  }

  bool get isRecurring => seriesId.isNotEmpty && recurrence.isRecurring;

  int get remainingCents => budgetCents - totalCents;

  /// 0..1 del presupuesto consumido (solo subtract).
  double get budgetUsedRatio {
    if (budgetCents <= 0) return 0;
    return (totalCents / budgetCents).clamp(0.0, 1.0).toDouble();
  }

  ExpenseProjectStatus statusAt(DateTime now) {
    final today = _day(now);
    if (today.isBefore(startDate)) return ExpenseProjectStatus.upcoming;
    if (today.isAfter(endDate)) return ExpenseProjectStatus.finished;
    return ExpenseProjectStatus.active;
  }

  bool isOwner(String uid) => ownerId == uid;
}

// ════════════════════════════════════════════════════════════════════════════
// GASTO
// ════════════════════════════════════════════════════════════════════════════

class Expense {
  final String id;
  final String concept;
  final int amountCents;
  final DateTime date;
  final String paidByUid;
  final String paidByName;
  final String createdBy;
  final String note;
  final bool isInitial;

  const Expense({
    required this.id,
    required this.concept,
    required this.amountCents,
    required this.date,
    required this.paidByUid,
    this.paidByName = '',
    required this.createdBy,
    this.note = '',
    this.isInitial = false,
  });

  factory Expense.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    final raw = d['date'];
    final date = raw is Timestamp
        ? raw.toDate()
        : (raw is int
              ? DateTime.fromMillisecondsSinceEpoch(raw)
              : DateTime.now());
    return Expense(
      id: doc.id,
      concept: (d['concept'] as String?) ?? '',
      amountCents: (d['amount_cents'] as num?)?.toInt() ?? 0,
      date: _day(date),
      paidByUid: (d['paid_by_uid'] as String?) ?? '',
      paidByName: (d['paid_by_name'] as String?) ?? '',
      createdBy: (d['created_by'] as String?) ?? '',
      note: (d['note'] as String?) ?? '',
      isInitial: (d['is_initial'] as bool?) ?? false,
    );
  }

  Expense copyWith({
    String? concept,
    int? amountCents,
    DateTime? date,
    String? paidByUid,
    String? paidByName,
    String? note,
  }) => Expense(
    id: id,
    concept: concept ?? this.concept,
    amountCents: amountCents ?? this.amountCents,
    date: date ?? this.date,
    paidByUid: paidByUid ?? this.paidByUid,
    paidByName: paidByName ?? this.paidByName,
    createdBy: createdBy,
    note: note ?? this.note,
    isInitial: isInitial,
  );
}

/// Lista de gastos + si viene confirmada por el servidor (sin escrituras
/// pendientes). Se usa para corregir los totales agregados solo con datos
/// definitivos.
class ExpenseListSnapshot {
  final List<Expense> items;
  final bool fromServer;
  const ExpenseListSnapshot(this.items, this.fromServer);
}

// ════════════════════════════════════════════════════════════════════════════
// SERIE (plantilla de proyecto periódico)
// ════════════════════════════════════════════════════════════════════════════

class ExpenseSeries {
  final String id;
  final String ownerId;
  final String ownerName;
  final List<String> members;
  final Map<String, String> memberNames;
  final String title;
  final String description;
  final ExpenseProjectType type;
  final int budgetCents;
  final ExpenseRecurrence recurrence;
  final DateTime anchorStart;
  final int durationDays;
  final bool fullPeriod;
  final int nextIndex;
  final bool active;
  final List<InitialExpense> initialExpenses;

  const ExpenseSeries({
    required this.id,
    required this.ownerId,
    this.ownerName = '',
    this.members = const [],
    this.memberNames = const {},
    required this.title,
    this.description = '',
    required this.type,
    this.budgetCents = 0,
    required this.recurrence,
    required this.anchorStart,
    this.durationDays = 0,
    this.fullPeriod = true,
    this.nextIndex = 1,
    this.active = true,
    this.initialExpenses = const [],
  });

  factory ExpenseSeries.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    final rawAnchor = d['anchor_start'];
    final anchor = rawAnchor is Timestamp
        ? _day(rawAnchor.toDate())
        : _day(DateTime.now());
    return ExpenseSeries(
      id: doc.id,
      ownerId: (d['owner_id'] as String?) ?? '',
      ownerName: (d['owner_name'] as String?) ?? '',
      members: List<String>.from(d['members'] ?? const []),
      memberNames: _stringMap(d['member_names']),
      title: (d['title'] as String?) ?? '',
      description: (d['description'] as String?) ?? '',
      type: ExpenseProjectTypeX.fromKey(d['type'] as String?),
      budgetCents: (d['budget_cents'] as num?)?.toInt() ?? 0,
      recurrence: ExpenseRecurrenceX.fromKey(d['recurrence'] as String?),
      anchorStart: anchor,
      durationDays: (d['duration_days'] as num?)?.toInt() ?? 0,
      fullPeriod: (d['full_period'] as bool?) ?? true,
      nextIndex: (d['next_index'] as num?)?.toInt() ?? 1,
      active: (d['active'] as bool?) ?? true,
      initialExpenses: ((d['initial_expenses'] as List?) ?? const [])
          .whereType<Map>()
          .map((m) => InitialExpense.fromMap(Map<String, dynamic>.from(m)))
          .toList(),
    );
  }

  DateTime startOf(int n) => occurrenceStart(anchorStart, recurrence, n);

  DateTime endOf(int n) => occurrenceEnd(
    anchorStart,
    recurrence,
    n,
    fullPeriod: fullPeriod,
    durationDays: durationDays,
  );
}

// ════════════════════════════════════════════════════════════════════════════
// HELPERS
// ════════════════════════════════════════════════════════════════════════════

Map<String, String> _stringMap(dynamic raw) {
  if (raw is! Map) return const {};
  return raw.map((k, v) => MapEntry(k.toString(), (v ?? '').toString()));
}

Map<String, int> _intMap(dynamic raw) {
  if (raw is! Map) return const {};
  return raw.map((k, v) => MapEntry(k.toString(), v is num ? v.toInt() : 0));
}
