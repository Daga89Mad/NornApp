// lib/models/weekly_menu_model.dart

class WeeklyMenuEntry {
  final String id;
  final int date;
  final String mealType;
  final String title;
  final String description;
  final String ownerId;
  final String ownerName; // nombre del dueño para mostrar en items compartidos
  final String sharedWith; // JSON-encoded list de UIDs, p.ej. '["uid1","uid2"]'
  final int synced;

  const WeeklyMenuEntry({
    required this.id,
    required this.date,
    required this.mealType,
    required this.title,
    this.description = '',
    required this.ownerId,
    this.ownerName = '',
    this.sharedWith = '',
    this.synced = 0,
  });

  factory WeeklyMenuEntry.fromMap(Map<String, dynamic> m) => WeeklyMenuEntry(
    id: m['id'] as String,
    date: m['date'] as int,
    mealType: (m['meal_type'] as String?) ?? 'Comida',
    title: (m['title'] as String?) ?? '',
    description: (m['description'] as String?) ?? '',
    ownerId: (m['owner_id'] as String?) ?? '',
    ownerName: (m['owner_name'] as String?) ?? '',
    sharedWith: (m['shared_with'] as String?) ?? '',
    synced: (m['synced'] as int?) ?? 0,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'date': date,
    'meal_type': mealType,
    'title': title,
    'description': description,
    'owner_id': ownerId,
    'owner_name': ownerName,
    'shared_with': sharedWith,
    'synced': synced,
  };

  WeeklyMenuEntry copyWith({
    String? id,
    int? date,
    String? mealType,
    String? title,
    String? description,
    String? ownerId,
    String? ownerName,
    String? sharedWith,
    int? synced,
  }) => WeeklyMenuEntry(
    id: id ?? this.id,
    date: date ?? this.date,
    mealType: mealType ?? this.mealType,
    title: title ?? this.title,
    description: description ?? this.description,
    ownerId: ownerId ?? this.ownerId,
    ownerName: ownerName ?? this.ownerName,
    sharedWith: sharedWith ?? this.sharedWith,
    synced: synced ?? this.synced,
  );

  bool isSharedFromOther(String myUid) =>
      ownerId.isNotEmpty && ownerId != myUid;

  static const List<String> mealTypes = [
    'Desayuno',
    'Almuerzo',
    'Merienda',
    'Cena',
    'Otro',
  ];

  static int normalizeToMidnight(DateTime d) =>
      DateTime(d.year, d.month, d.day).millisecondsSinceEpoch;
}
