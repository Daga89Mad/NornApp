// lib/models/event_item.dart
import 'package:flutter/material.dart';

enum Category { Laboral, Evento, Recordatorio, Cita, Bebe, Periodo }

enum Tipo {
  Horario,
  Reunion,
  Entrega,
  Cumpleanos,
  Aniversario,
  Boda,
  Comunion,
  Checklist,
  Bautizo,
  Despedida,
  Otros,
}

class EventItem {
  final String? id;
  final Category category;
  final Tipo tipo;
  final String title;
  final String description;
  final String icon;
  final String creator;
  final List<String> users;
  final TimeOfDay from;
  final TimeOfDay to;
  final Color color;
  final bool hasAlarm;
  final DateTime? alarmAt;
  final bool hasNotification;
  final DateTime? notificationAt;
  final bool soloParaMi;
  // ownerId: UID de Firebase del propietario.
  // null = evento propio (creado antes de este campo).
  final String? ownerId;

  const EventItem({
    this.id,
    required this.category,
    required this.tipo,
    required this.title,
    required this.description,
    required this.icon,
    required this.creator,
    required this.users,
    required this.from,
    required this.to,
    required this.color,
    this.hasAlarm = false,
    this.alarmAt,
    this.hasNotification = false,
    this.notificationAt,
    this.soloParaMi = false,
    this.ownerId,
  });

  EventItem copyWith({
    String? id,
    Category? category,
    Tipo? tipo,
    String? title,
    String? description,
    String? icon,
    String? creator,
    List<String>? users,
    TimeOfDay? from,
    TimeOfDay? to,
    Color? color,
    bool? hasAlarm,
    DateTime? alarmAt,
    bool? hasNotification,
    DateTime? notificationAt,
    bool? soloParaMi,
    String? ownerId,
  }) => EventItem(
    id: id ?? this.id,
    category: category ?? this.category,
    tipo: tipo ?? this.tipo,
    title: title ?? this.title,
    description: description ?? this.description,
    icon: icon ?? this.icon,
    creator: creator ?? this.creator,
    users: users ?? this.users,
    from: from ?? this.from,
    to: to ?? this.to,
    color: color ?? this.color,
    hasAlarm: hasAlarm ?? this.hasAlarm,
    alarmAt: alarmAt ?? this.alarmAt,
    hasNotification: hasNotification ?? this.hasNotification,
    notificationAt: notificationAt ?? this.notificationAt,
    soloParaMi: soloParaMi ?? this.soloParaMi,
    ownerId: ownerId ?? this.ownerId,
  );
}
