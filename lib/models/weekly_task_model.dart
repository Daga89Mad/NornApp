// lib/models/weekly_task_model.dart

class WeeklyTask {
  final String id;
  final int date;
  final String title;
  final String description;
  final bool isDone;
  final String ownerId;
  final String ownerName; // nombre del dueño para mostrar en items compartidos
  final String sharedWith; // JSON-encoded list de UIDs
  final int synced;
  final String recurrence; // 'none' | 'daily' | 'weekly'

  const WeeklyTask({
    required this.id,
    required this.date,
    required this.title,
    this.description = '',
    this.isDone = false,
    required this.ownerId,
    this.ownerName = '',
    this.sharedWith = '',
    this.synced = 0,
    this.recurrence = 'none',
  });

  factory WeeklyTask.fromMap(Map<String, dynamic> m) => WeeklyTask(
    id: m['id'] as String,
    date: m['date'] as int,
    title: (m['title'] as String?) ?? '',
    description: (m['description'] as String?) ?? '',
    isDone: ((m['is_done'] as int?) ?? 0) == 1,
    ownerId: (m['owner_id'] as String?) ?? '',
    ownerName: (m['owner_name'] as String?) ?? '',
    sharedWith: (m['shared_with'] as String?) ?? '',
    synced: (m['synced'] as int?) ?? 0,
    recurrence: (m['recurrence'] as String?) ?? 'none',
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'date': date,
    'title': title,
    'description': description,
    'is_done': isDone ? 1 : 0,
    'owner_id': ownerId,
    'owner_name': ownerName,
    'shared_with': sharedWith,
    'synced': synced,
    'recurrence': recurrence,
  };

  WeeklyTask copyWith({
    String? id,
    int? date,
    String? title,
    String? description,
    bool? isDone,
    String? ownerId,
    String? ownerName,
    String? sharedWith,
    int? synced,
    String? recurrence,
  }) => WeeklyTask(
    id: id ?? this.id,
    date: date ?? this.date,
    title: title ?? this.title,
    description: description ?? this.description,
    isDone: isDone ?? this.isDone,
    ownerId: ownerId ?? this.ownerId,
    ownerName: ownerName ?? this.ownerName,
    sharedWith: sharedWith ?? this.sharedWith,
    synced: synced ?? this.synced,
    recurrence: recurrence ?? this.recurrence,
  );

  bool isSharedFromOther(String myUid) =>
      ownerId.isNotEmpty && ownerId != myUid;

  static int normalizeToMidnight(DateTime d) =>
      DateTime(d.year, d.month, d.day).millisecondsSinceEpoch;
}
