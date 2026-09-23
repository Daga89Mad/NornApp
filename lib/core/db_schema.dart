// lib/core/db_schema.dart
class DBSchema {
  static const int version = 24; // ← v24: image_data en weekly_trainings

  static const String tableUsers = 'users';
  static const String tableEvents = 'events';
  static const String tableChecklist = 'checklist_items';
  static const String tableShifts = 'shifts';
  static const String tableShiftAssignments = 'shift_assignments';
  static const String tableJokes = 'jokes';
  static const String tablePhrases = 'phrases';
  static const String tableLanguageWords = 'language_words';
  static const String tableFacts = 'interesting_facts';
  static const String tableFriends = 'friends';
  static const String tableWeeklyMenus = 'weekly_menus';
  static const String tableWeeklyTasks = 'weekly_tasks';
  static const String tableWeeklyTrainings = 'weekly_trainings';
  static const String tableDismissedShared = 'dismissed_shared';
  static const String tableSharedDateOverrides =
      'shared_date_overrides'; // ← NUEVO
  static const String tablePendingDateChanges =
      'pending_date_changes'; // ← NUEVO

  static const String createUsers =
      """CREATE TABLE users (id TEXT PRIMARY KEY, email TEXT NOT NULL, name TEXT, last_sync INTEGER)""";

  static const String createEvents = """
    CREATE TABLE events (
      id TEXT PRIMARY KEY, title TEXT NOT NULL, description TEXT NOT NULL DEFAULT '',
      date INTEGER NOT NULL, from_minutes INTEGER NOT NULL DEFAULT 0,
      to_minutes INTEGER NOT NULL DEFAULT 60, category TEXT NOT NULL DEFAULT 'Evento',
      tipo TEXT NOT NULL DEFAULT 'Otros', icon TEXT NOT NULL DEFAULT '',
      creator TEXT NOT NULL DEFAULT '', users TEXT NOT NULL DEFAULT '',
      color INTEGER NOT NULL DEFAULT 4280391411, owner_id TEXT,
      synced INTEGER NOT NULL DEFAULT 0, has_alarm INTEGER NOT NULL DEFAULT 0,
      alarm_at INTEGER, has_notification INTEGER NOT NULL DEFAULT 0,
      notification_at INTEGER, solo_para_mi INTEGER NOT NULL DEFAULT 0
    )
  """;

  static const String createChecklist = """
    CREATE TABLE checklist_items (
      id TEXT PRIMARY KEY,
      event_id TEXT NOT NULL,
      text TEXT NOT NULL,
      is_checked INTEGER NOT NULL DEFAULT 0,
      position INTEGER NOT NULL DEFAULT 0
    )
  """;

  static const String createShifts =
      """CREATE TABLE shifts (id TEXT PRIMARY KEY, name TEXT NOT NULL, color INTEGER NOT NULL, from_minutes INTEGER NOT NULL DEFAULT 0, to_minutes INTEGER NOT NULL DEFAULT 0, euro_per_hour REAL, sort_order INTEGER NOT NULL DEFAULT 0)""";

  static const String createShiftAssignments = """
    CREATE TABLE shift_assignments (
      id TEXT PRIMARY KEY,
      shift_id TEXT NOT NULL,
      date INTEGER NOT NULL,
      owner_id TEXT,
      shift_name TEXT NOT NULL DEFAULT '',
      shift_color INTEGER NOT NULL DEFAULT 4280391411,
      shift_from_minutes INTEGER NOT NULL DEFAULT 0,
      shift_to_minutes INTEGER NOT NULL DEFAULT 0
    )
  """;

  static const String createJokes =
      """CREATE TABLE jokes (id INTEGER PRIMARY KEY AUTOINCREMENT, text TEXT NOT NULL)""";

  // ── CORREGIDO: incluye columna author ──────────────────────────────────────
  static const String createPhrases = """
    CREATE TABLE phrases (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      text TEXT NOT NULL,
      author TEXT NOT NULL DEFAULT ''
    )
  """;

  // ── CORREGIDO: columnas reales de idioms (phrase/pronunciation/meaning/...) ─
  static const String createLanguageWords = """
    CREATE TABLE language_words (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      language TEXT NOT NULL,
      phrase TEXT NOT NULL,
      pronunciation TEXT NOT NULL DEFAULT '',
      meaning TEXT NOT NULL,
      example TEXT NOT NULL DEFAULT '',
      example_pronunciation TEXT NOT NULL DEFAULT ''
    )
  """;

  // ── CORREGIDO: incluye columna category ────────────────────────────────────
  static const String createFacts = """
    CREATE TABLE interesting_facts (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      text TEXT NOT NULL,
      category TEXT NOT NULL DEFAULT ''
    )
  """;

  static const String createFriends = """
    CREATE TABLE friends (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      email TEXT NOT NULL DEFAULT '',
      alias TEXT NOT NULL DEFAULT '',
      logo TEXT NOT NULL DEFAULT '😊',
      firebase_uid TEXT,
      owner_id TEXT
    )
  """;

  static const String createWeeklyMenus = """
    CREATE TABLE weekly_menus (
      id TEXT PRIMARY KEY,
      date INTEGER NOT NULL,
      meal_type TEXT NOT NULL DEFAULT 'Comida',
      title TEXT NOT NULL,
      description TEXT NOT NULL DEFAULT '',
      owner_id TEXT NOT NULL DEFAULT '',
      owner_name TEXT NOT NULL DEFAULT '',
      shared_with TEXT NOT NULL DEFAULT '',
      synced INTEGER NOT NULL DEFAULT 0
    )
  """;

  static const String createWeeklyTasks = """
    CREATE TABLE weekly_tasks (
      id TEXT PRIMARY KEY,
      date INTEGER NOT NULL,
      title TEXT NOT NULL,
      description TEXT NOT NULL DEFAULT '',
      is_done INTEGER NOT NULL DEFAULT 0,
      owner_id TEXT NOT NULL DEFAULT '',
      owner_name TEXT NOT NULL DEFAULT '',
      shared_with TEXT NOT NULL DEFAULT '',
      recurrence TEXT NOT NULL DEFAULT 'none',
      parent_id TEXT NOT NULL DEFAULT '',      -- ← subtareas
      synced INTEGER NOT NULL DEFAULT 0
    )
  """;

  // ── Entrenamiento semanal ────────────────────────────────────────────────
  static const String createWeeklyTrainings = """
    CREATE TABLE weekly_trainings (
      id TEXT PRIMARY KEY,
      date INTEGER NOT NULL,
      training_type TEXT NOT NULL DEFAULT 'Otro',
      title TEXT NOT NULL,
      description TEXT NOT NULL DEFAULT '',
      is_done INTEGER NOT NULL DEFAULT 0,
      owner_id TEXT NOT NULL DEFAULT '',
      owner_name TEXT NOT NULL DEFAULT '',
      shared_with TEXT NOT NULL DEFAULT '',
      synced INTEGER NOT NULL DEFAULT 0,
      image_data TEXT NOT NULL DEFAULT ''
    )
  """;

  static const String tableCalendarCategories =
      'calendar_categories'; // ← NUEVO

  static const String createCalendarCategories = """
    CREATE TABLE calendar_categories (
      id TEXT PRIMARY KEY,
      label TEXT NOT NULL,
      color INTEGER NOT NULL DEFAULT 4280391411,
      icon TEXT NOT NULL DEFAULT '🏷️',
      owner_id TEXT,
      synced INTEGER NOT NULL DEFAULT 0
    )
  """;

  // ── NUEVO: items compartidos que el usuario ha ocultado ("quitar") ──────────
  // No se borran para el dueño; solo se ocultan en mi vista. Si el dueño deja
  // de compartírmelos y vuelve a hacerlo, reaparecen (ver DismissedSharedService).
  static const String createDismissedShared = """
    CREATE TABLE dismissed_shared (
      item_id TEXT NOT NULL,
      item_type TEXT NOT NULL,
      PRIMARY KEY (item_id, item_type)
    )
  """;

  // ── NUEVO: fecha local personalizada para un item COMPARTIDO ───────────────
  // Cuando alguien mueve de día un item que no es suyo, el cambio se aplica
  // de inmediato en SU calendario mediante esta tabla, y al dueño y al resto
  // se les envía una propuesta (ver pending_date_changes). Cuando la propuesta
  // se acepta y la fecha real ya coincide, el override se borra solo.
  static const String createSharedDateOverrides = """
    CREATE TABLE shared_date_overrides (
      item_id TEXT NOT NULL,
      item_type TEXT NOT NULL,
      date INTEGER NOT NULL,
      PRIMARY KEY (item_id, item_type)
    )
  """;

  // ── NUEVO: propuestas de cambio de fecha pendientes de responder ───────────
  // Espejo local de los documentos 'date_change_requests' de Firestore en los
  // que yo aparezco como pendiente. Se muestran al entrar en la pantalla
  // correspondiente (tareas, menús o entrenamiento).
  static const String createPendingDateChanges = """
    CREATE TABLE pending_date_changes (
      id TEXT PRIMARY KEY,
      item_id TEXT NOT NULL,
      item_type TEXT NOT NULL,
      item_title TEXT NOT NULL DEFAULT '',
      owner_id TEXT NOT NULL DEFAULT '',
      from_uid TEXT NOT NULL DEFAULT '',
      from_name TEXT NOT NULL DEFAULT '',
      old_date INTEGER NOT NULL DEFAULT 0,
      new_date INTEGER NOT NULL DEFAULT 0,
      created_at INTEGER NOT NULL DEFAULT 0
    )
  """;
}
