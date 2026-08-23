// lib/models/weekly_training_model.dart

class WeeklyTrainingEntry {
  final String id;
  final int date;
  final String
  trainingType; // grupo/tipo de entrenamiento (como meal_type en menús)
  final String title;
  final String description;
  final bool isDone; // ← casilla "completado" (como en tareas)
  final String ownerId;
  final String ownerName; // nombre del dueño para mostrar en items compartidos
  final String sharedWith; // JSON-encoded list de UIDs, p.ej. '["uid1","uid2"]'
  final int synced;

  const WeeklyTrainingEntry({
    required this.id,
    required this.date,
    this.trainingType = 'Otro',
    required this.title,
    this.description = '',
    this.isDone = false,
    required this.ownerId,
    this.ownerName = '',
    this.sharedWith = '',
    this.synced = 0,
  });

  factory WeeklyTrainingEntry.fromMap(Map<String, dynamic> m) =>
      WeeklyTrainingEntry(
        id: m['id'] as String,
        date: m['date'] as int,
        trainingType: (m['training_type'] as String?) ?? 'Otro',
        title: (m['title'] as String?) ?? '',
        description: (m['description'] as String?) ?? '',
        isDone: ((m['is_done'] as int?) ?? 0) == 1,
        ownerId: (m['owner_id'] as String?) ?? '',
        ownerName: (m['owner_name'] as String?) ?? '',
        sharedWith: (m['shared_with'] as String?) ?? '',
        synced: (m['synced'] as int?) ?? 0,
      );

  Map<String, dynamic> toMap() => {
    'id': id,
    'date': date,
    'training_type': trainingType,
    'title': title,
    'description': description,
    'is_done': isDone ? 1 : 0,
    'owner_id': ownerId,
    'owner_name': ownerName,
    'shared_with': sharedWith,
    'synced': synced,
  };

  WeeklyTrainingEntry copyWith({
    String? id,
    int? date,
    String? trainingType,
    String? title,
    String? description,
    bool? isDone,
    String? ownerId,
    String? ownerName,
    String? sharedWith,
    int? synced,
  }) => WeeklyTrainingEntry(
    id: id ?? this.id,
    date: date ?? this.date,
    trainingType: trainingType ?? this.trainingType,
    title: title ?? this.title,
    description: description ?? this.description,
    isDone: isDone ?? this.isDone,
    ownerId: ownerId ?? this.ownerId,
    ownerName: ownerName ?? this.ownerName,
    sharedWith: sharedWith ?? this.sharedWith,
    synced: synced ?? this.synced,
  );

  bool isSharedFromOther(String myUid) =>
      ownerId.isNotEmpty && ownerId != myUid;

  /// Tipos de entrenamiento disponibles (equivalente a mealTypes en menús).
  static const List<String> trainingTypes = [
    'Pecho',
    'Espalda',
    'Pierna',
    'Hombro',
    'Brazo',
    'Core',
    'Cardio',
    'Full body',
    'Estiramiento',
    'Descanso',
    'Otro',
  ];

  static int normalizeToMidnight(DateTime d) =>
      DateTime(d.year, d.month, d.day).millisecondsSinceEpoch;
}
