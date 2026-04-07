// lib/core/event_repository.dart
import 'dart:math';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../models/event_item.dart';
import 'alarm_service.dart';
import 'db_provider.dart';
import 'db_schema.dart';
import 'firebase_sync_service.dart';

class EventRepository {
  EventRepository._();
  static final EventRepository instance = EventRepository._();

  String _generateId() {
    final rand = Random();
    final suffix = List.generate(
      8,
      (_) => rand.nextInt(36).toRadixString(36),
    ).join();
    return '${DateTime.now().millisecondsSinceEpoch}_$suffix';
  }

  Map<String, dynamic> _toMap(EventItem e, DateTime date) {
    final dayUtc = DateTime.utc(date.year, date.month, date.day);
    return {
      'id': e.id ?? _generateId(),
      'title': e.title,
      'description': e.description,
      'date': dayUtc.millisecondsSinceEpoch,
      'from_minutes': e.from.hour * 60 + e.from.minute,
      'to_minutes': e.to.hour * 60 + e.to.minute,
      'category': e.category.name,
      'tipo': e.tipo.name,
      'icon': e.icon,
      'creator': e.creator,
      'users': e.users.join('|'),
      'color': e.color.value,
      'owner_id': e.ownerId ?? FirebaseAuth.instance.currentUser?.uid,
      'synced': 0,
      'has_alarm': e.hasAlarm ? 1 : 0,
      'alarm_at': e.alarmAt?.millisecondsSinceEpoch,
      'has_notification': e.hasNotification ? 1 : 0,
      'notification_at': e.notificationAt?.millisecondsSinceEpoch,
      'solo_para_mi': e.soloParaMi ? 1 : 0,
    };
  }

  EventItem _fromMap(Map<String, dynamic> m) {
    final fromMin = (m['from_minutes'] as int?) ?? 0;
    final toMin = (m['to_minutes'] as int?) ?? 60;

    Category parseCategory(String? n) {
      if (n == null) return Category.Evento;
      try {
        return Category.values.firstWhere((c) => c.name == n);
      } catch (_) {
        return Category.Evento;
      }
    }

    Tipo parseTipo(String? n) {
      if (n == null) return Tipo.Otros;
      try {
        return Tipo.values.firstWhere((t) => t.name == n);
      } catch (_) {
        return Tipo.Otros;
      }
    }

    final usersRaw = (m['users'] as String?) ?? '';
    final alarmMs = m['alarm_at'] as int?;
    final notifMs = m['notification_at'] as int?;

    return EventItem(
      id: m['id'] as String?,
      category: parseCategory(m['category'] as String?),
      tipo: parseTipo(m['tipo'] as String?),
      title: (m['title'] as String?) ?? '',
      description: (m['description'] as String?) ?? '',
      icon: (m['icon'] as String?) ?? '📅',
      creator: (m['creator'] as String?) ?? '',
      users: usersRaw.isEmpty ? [] : usersRaw.split('|'),
      from: TimeOfDay(hour: fromMin ~/ 60, minute: fromMin % 60),
      to: TimeOfDay(hour: toMin ~/ 60, minute: toMin % 60),
      color: Color((m['color'] as int?) ?? Colors.blue.value),
      hasAlarm: ((m['has_alarm'] as int?) ?? 0) == 1,
      alarmAt: alarmMs != null
          ? DateTime.fromMillisecondsSinceEpoch(alarmMs)
          : null,
      hasNotification: ((m['has_notification'] as int?) ?? 0) == 1,
      notificationAt: notifMs != null
          ? DateTime.fromMillisecondsSinceEpoch(notifMs)
          : null,
      soloParaMi: ((m['solo_para_mi'] as int?) ?? 0) == 1,
      ownerId: m['owner_id'] as String?,
    );
  }

  // ── Queries ────────────────────────────────────────────────────────────────

  Future<List<EventItem>> getEventsForDay(DateTime day) async {
    final dayMs = DateTime.utc(
      day.year,
      day.month,
      day.day,
    ).millisecondsSinceEpoch;
    final rows = await DBProvider.db.query(
      DBSchema.tableEvents,
      where: 'date = ?',
      whereArgs: [dayMs],
      orderBy: 'from_minutes ASC',
    );
    return rows.map(_fromMap).toList();
  }

  Future<Map<DateTime, List<EventItem>>> getEventsForMonth(
    int year,
    int month,
  ) async {
    final firstMs = DateTime.utc(year, month, 1).millisecondsSinceEpoch;
    final lastMs = DateTime.utc(year, month + 1, 1).millisecondsSinceEpoch - 1;
    final rows = await DBProvider.db.query(
      DBSchema.tableEvents,
      where: 'date >= ? AND date <= ?',
      whereArgs: [firstMs, lastMs],
      orderBy: 'from_minutes ASC',
    );
    final Map<DateTime, List<EventItem>> result = {};
    for (final row in rows) {
      final key = DateTime.fromMillisecondsSinceEpoch(
        row['date'] as int,
        isUtc: true,
      );
      result.putIfAbsent(key, () => []).add(_fromMap(row));
    }
    return result;
  }

  // ── Escritura ──────────────────────────────────────────────────────────────

  Future<EventItem> save(EventItem event, DateTime date) async {
    final id = event.id ?? _generateId();
    final withId = event.copyWith(id: id);

    // 1. SQLite
    await DBProvider.db.insertOrReplace(
      DBSchema.tableEvents,
      _toMap(withId, date),
    );

    // 2. Alarmas locales
    if (withId.hasAlarm && withId.alarmAt != null) {
      await AlarmService.instance.schedule(
        eventId: id,
        title: '⏰ ${withId.title}',
        body: withId.description.isNotEmpty
            ? withId.description
            : 'Alarma de evento',
        fireAt: withId.alarmAt!,
        type: AlarmType.alarm,
      );
    } else {
      await AlarmService.instance.cancel(id, AlarmType.alarm);
    }
    if (withId.hasNotification && withId.notificationAt != null) {
      await AlarmService.instance.schedule(
        eventId: id,
        title: '🔔 ${withId.title}',
        body: withId.description.isNotEmpty
            ? withId.description
            : 'Recordatorio',
        fireAt: withId.notificationAt!,
        type: AlarmType.notification,
      );
    } else {
      await AlarmService.instance.cancel(id, AlarmType.notification);
    }

    // 3. Firebase (solo si no es soloParaMi)
    await FirebaseSyncService.instance.pushEvent(withId, date);

    debugPrint('💾 Evento guardado: $id');
    return withId;
  }

  Future<void> saveAll(List<MapEntry<DateTime, EventItem>> entries) async {
    final rows = entries.map((e) {
      final id = e.value.id ?? _generateId();
      return _toMap(e.value.copyWith(id: id), e.key);
    }).toList();
    await DBProvider.db.batchInsert(DBSchema.tableEvents, rows);
  }

  Future<void> delete(String id) async {
    await AlarmService.instance.cancelAll(id);
    await DBProvider.db.delete(
      DBSchema.tableEvents,
      where: 'id = ?',
      whereArgs: [id],
    );
    await FirebaseSyncService.instance.deleteEvent(id);
    debugPrint('🗑️ Evento eliminado: $id');
  }

  Future<void> deleteAllForDay(DateTime day) async {
    final events = await getEventsForDay(day);
    for (final e in events) {
      if (e.id != null) {
        await AlarmService.instance.cancelAll(e.id!);
        await FirebaseSyncService.instance.deleteEvent(e.id!);
      }
    }
    final dayMs = DateTime.utc(
      day.year,
      day.month,
      day.day,
    ).millisecondsSinceEpoch;
    await DBProvider.db.delete(
      DBSchema.tableEvents,
      where: 'date = ?',
      whereArgs: [dayMs],
    );
  }

  // ── Helpers estáticos ──────────────────────────────────────────────────────

  static Color colorForCategory(Category cat) {
    switch (cat) {
      case Category.Laboral:
        return Colors.blue;
      case Category.Evento:
        return Colors.amber;
      case Category.Recordatorio:
        return Colors.red;
      case Category.Cita:
        return Colors.orange;
      case Category.Bebe:
        return Colors.pink;
      case Category.Periodo:
        return Colors.deepPurple;
    }
  }

  static String iconForCategory(Category cat) {
    switch (cat) {
      case Category.Laboral:
        return '🧑‍💼';
      case Category.Evento:
        return '🎉';
      case Category.Recordatorio:
        return '🔔';
      case Category.Cita:
        return '📋';
      case Category.Bebe:
        return '🍼';
      case Category.Periodo:
        return '🔴';
    }
  }

  static String categoryToString(Category cat) {
    switch (cat) {
      case Category.Laboral:
        return 'Trabajo';
      case Category.Evento:
        return 'Eventos';
      case Category.Cita:
        return 'Citas';
      case Category.Recordatorio:
        return 'Recordatorios';
      case Category.Bebe:
        return 'Bebé';
      case Category.Periodo:
        return 'Período';
    }
  }

  static Category categoryFromString(String s) {
    switch (s) {
      case 'Trabajo':
        return Category.Laboral;
      case 'Eventos':
        return Category.Evento;
      case 'Citas':
        return Category.Cita;
      case 'Recordatorios':
        return Category.Recordatorio;
      case 'Bebé':
        return Category.Bebe;
      case 'Período':
        return Category.Periodo;
      default:
        return Category.Evento;
    }
  }
}
