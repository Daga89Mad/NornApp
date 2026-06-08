// lib/models/calendar_category.dart
import 'package:flutter/material.dart';
import 'event_item.dart';
import '../core/event_repository.dart';

/// Categoría del calendario, integrada (basada en el enum [Category]) o
/// personalizada por el usuario. La identidad estable es [key]:
///   - Integradas: el nombre del enum (p. ej. "Laboral", "Evento").
///   - Personalizadas: un id generado único (p. ej. "cat_1700000000_ab12cd").
class CalendarCategory {
  final String key;
  final String label;
  final Color color;
  final String icon; // emoji
  final bool isBuiltIn;
  final String? ownerId; // null en las integradas
  final bool synced;

  const CalendarCategory({
    required this.key,
    required this.label,
    required this.color,
    required this.icon,
    this.isBuiltIn = false,
    this.ownerId,
    this.synced = false,
  });

  bool get isCustom => !isBuiltIn;

  CalendarCategory copyWith({
    String? key,
    String? label,
    Color? color,
    String? icon,
    bool? isBuiltIn,
    String? ownerId,
    bool? synced,
  }) => CalendarCategory(
    key: key ?? this.key,
    label: label ?? this.label,
    color: color ?? this.color,
    icon: icon ?? this.icon,
    isBuiltIn: isBuiltIn ?? this.isBuiltIn,
    ownerId: ownerId ?? this.ownerId,
    synced: synced ?? this.synced,
  );

  // ── Integradas ──────────────────────────────────────────────────────────
  factory CalendarCategory.fromBuiltIn(Category c) => CalendarCategory(
    key: c.name,
    label: EventRepository.categoryToString(c),
    color: EventRepository.colorForCategory(c),
    icon: EventRepository.iconForCategory(c),
    isBuiltIn: true,
  );

  static List<CalendarCategory> builtIns() =>
      Category.values.map(CalendarCategory.fromBuiltIn).toList();

  // ── BD local ──────────────────────────────────────────────────────────────
  Map<String, dynamic> toMap() => {
    'id': key,
    'label': label,
    'color': color.value,
    'icon': icon,
    'owner_id': ownerId,
    'synced': synced ? 1 : 0,
  };

  factory CalendarCategory.fromMap(Map<String, dynamic> m) => CalendarCategory(
    key: m['id'] as String,
    label: (m['label'] as String?) ?? '',
    color: Color((m['color'] as int?) ?? Colors.indigo.value),
    icon: (m['icon'] as String?) ?? '🏷️',
    isBuiltIn: false,
    ownerId: m['owner_id'] as String?,
    synced: ((m['synced'] as int?) ?? 0) == 1,
  );

  // ── Firestore ─────────────────────────────────────────────────────────────
  Map<String, dynamic> toFirestore() => {
    'key': key,
    'label': label,
    'color': color.value,
    'icon': icon,
    'owner_id': ownerId,
  };

  factory CalendarCategory.fromFirestore(Map<String, dynamic> d) =>
      CalendarCategory(
        key: d['key'] as String,
        label: (d['label'] as String?) ?? '',
        color: Color((d['color'] as int?) ?? Colors.indigo.value),
        icon: (d['icon'] as String?) ?? '🏷️',
        isBuiltIn: false,
        ownerId: d['owner_id'] as String?,
        synced: true,
      );
}
