// lib/models/shift_assignment.dart

class ShiftAssignment {
  final String? id;
  final String shiftId;
  final DateTime date; // siempre UTC, solo año/mes/día

  const ShiftAssignment({this.id, required this.shiftId, required this.date});
}
