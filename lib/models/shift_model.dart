// lib/models/shift_model.dart

import 'package:flutter/material.dart';

class ShiftModel {
  final String? id;
  final String name;
  final Color color;
  final TimeOfDay from;
  final TimeOfDay to;
  final double? euroPerHour; // opcional
  final int sortOrder;

  const ShiftModel({
    this.id,
    required this.name,
    required this.color,
    required this.from,
    required this.to,
    this.euroPerHour,
    this.sortOrder = 0,
  });

  ShiftModel copyWith({
    String? id,
    String? name,
    Color? color,
    TimeOfDay? from,
    TimeOfDay? to,
    double? euroPerHour,
    bool clearEuro = false,
    int? sortOrder,
  }) {
    return ShiftModel(
      id: id ?? this.id,
      name: name ?? this.name,
      color: color ?? this.color,
      from: from ?? this.from,
      to: to ?? this.to,
      euroPerHour: clearEuro ? null : (euroPerHour ?? this.euroPerHour),
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  /// Duración en horas (cruzando medianoche si 'to' < 'from')
  double get durationHours {
    final fromMin = from.hour * 60 + from.minute;
    final toMin = to.hour * 60 + to.minute;
    final diff = toMin >= fromMin ? toMin - fromMin : (1440 - fromMin) + toMin;
    return diff / 60.0;
  }

  /// Ganancia por turno (null si no hay euro/hora)
  double? get earningsPerShift =>
      euroPerHour != null ? durationHours * euroPerHour! : null;
}
