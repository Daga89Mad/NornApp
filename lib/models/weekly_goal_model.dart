// lib/models/weekly_goal_model.dart
//
// Objetivo semanal: algo que se quiere conseguir durante una semana pero sin
// un día fijo (p. ej. "Perder 2 kilos" en Menús, "Escuchar un podcast" en
// Tareas o "Correr 20 km" en Entrenamiento).
//
// Se guarda en Firestore (colección 'weekly_goals') y se puede compartir con
// amigos igual que el resto de cosas semanales (campo 'shared_with').

import 'package:cloud_firestore/cloud_firestore.dart';

class WeeklyGoal {
  final String id;

  /// Pantalla a la que pertenece: 'menus' | 'tasks' | 'trainings'.
  final String type;

  /// Semana a la que pertenece, como 'AAAA-MM-DD' del lunes. Se usa texto y
  /// no milisegundos para que no le afecten el cambio de hora ni la zona
  /// horaria de quien lo tenga compartido.
  final String weekKey;

  final String title;
  final bool isDone;
  final String ownerId;
  final String ownerName;
  final List<String> sharedWith;

  const WeeklyGoal({
    required this.id,
    required this.type,
    required this.weekKey,
    required this.title,
    this.isDone = false,
    this.ownerId = '',
    this.ownerName = '',
    this.sharedWith = const [],
  });

  bool isSharedFromOther(String myUid) =>
      ownerId.isNotEmpty && ownerId != myUid;

  WeeklyGoal copyWith({
    String? id,
    String? type,
    String? weekKey,
    String? title,
    bool? isDone,
    String? ownerId,
    String? ownerName,
    List<String>? sharedWith,
  }) => WeeklyGoal(
    id: id ?? this.id,
    type: type ?? this.type,
    weekKey: weekKey ?? this.weekKey,
    title: title ?? this.title,
    isDone: isDone ?? this.isDone,
    ownerId: ownerId ?? this.ownerId,
    ownerName: ownerName ?? this.ownerName,
    sharedWith: sharedWith ?? this.sharedWith,
  );

  factory WeeklyGoal.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    return WeeklyGoal(
      id: doc.id,
      type: d['type'] as String? ?? 'tasks',
      weekKey: d['week_key'] as String? ?? '',
      title: d['title'] as String? ?? '',
      isDone: d['is_done'] as bool? ?? false,
      ownerId: d['owner_id'] as String? ?? '',
      ownerName: d['owner_name'] as String? ?? '',
      sharedWith: List<String>.from(d['shared_with'] ?? const []),
    );
  }

  Map<String, dynamic> toFirestore() => {
    'type': type,
    'week_key': weekKey,
    'title': title,
    'is_done': isDone,
    'owner_id': ownerId,
    'owner_name': ownerName,
    'shared_with': sharedWith,
    'updated_at': FieldValue.serverTimestamp(),
  };

  /// Clave de semana ('AAAA-MM-DD' del lunes) para un lunes ya calculado.
  static String weekKeyOf(DateTime monday) =>
      '${monday.year.toString().padLeft(4, '0')}-'
      '${monday.month.toString().padLeft(2, '0')}-'
      '${monday.day.toString().padLeft(2, '0')}';
}
