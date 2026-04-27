// lib/core/db_schema.dart
class DBSchema {
  static const int version = 16; // ← subido de 15 a 16

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

  static const String createPhrases =
      """CREATE TABLE phrases (id INTEGER PRIMARY KEY AUTOINCREMENT, text TEXT NOT NULL)""";

  static const String createLanguageWords =
      """CREATE TABLE language_words (id INTEGER PRIMARY KEY AUTOINCREMENT, word TEXT NOT NULL, translation TEXT NOT NULL, language TEXT NOT NULL)""";

  static const String createFacts =
      """CREATE TABLE interesting_facts (id INTEGER PRIMARY KEY AUTOINCREMENT, text TEXT NOT NULL)""";

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
      synced INTEGER NOT NULL DEFAULT 0
    )
  """;
}
