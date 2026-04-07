// lib/core/alarm_service.dart
//
// Compatible con flutter_local_notifications ^18 (sin uiLocalNotificationDateInterpretation).
// Android: exactAllowWhileIdle + fullScreenIntent para alarmas reales.
// iOS:     DarwinNotificationDetails con interruptionLevel timeSensitive.

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

enum AlarmType { alarm, notification }

class AlarmService {
  AlarmService._();
  static final AlarmService instance = AlarmService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  // ── Canales ────────────────────────────────────────────────────────────────

  static const _alarmChannelId = 'fc_alarms';
  static const _alarmChannelName = 'Alarmas';
  static const _notifChannelId = 'fc_notifications';
  static const _notifChannelName = 'Notificaciones de eventos';

  // ── Init ───────────────────────────────────────────────────────────────────

  Future<void> init() async {
    if (_initialized) return;

    tz.initializeTimeZones();

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: ios),
      onDidReceiveNotificationResponse: _onTap,
    );

    // Permisos Android 13+
    final androidImpl = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidImpl?.requestNotificationsPermission();
    await androidImpl?.requestExactAlarmsPermission();

    _initialized = true;
    debugPrint('AlarmService inicializado');
  }

  /// Pide permiso explícito en iOS (llamar tras login).
  Future<bool> requestIosPermission() async {
    final iosImpl = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    final granted = await iosImpl?.requestPermissions(
      alert: true,
      badge: true,
      sound: true,
    );
    return granted ?? false;
  }

  void _onTap(NotificationResponse r) {
    debugPrint('Notificación pulsada id=${r.id} payload=${r.payload}');
  }

  // ── Scheduling ─────────────────────────────────────────────────────────────

  Future<void> schedule({
    required String eventId,
    required String title,
    required String body,
    required DateTime fireAt,
    required AlarmType type,
  }) async {
    if (!_initialized) await init();

    final tzFireAt = tz.TZDateTime.from(fireAt, tz.local);
    if (tzFireAt.isBefore(tz.TZDateTime.now(tz.local))) {
      debugPrint('⚠️ Fecha en el pasado, alarma no programada: $fireAt');
      return;
    }

    final notifId = _notifId(eventId, type);
    final details = type == AlarmType.alarm ? _alarmDetails() : _notifDetails();

    // ⚠️ En flutter_local_notifications ^18 se eliminó
    // uiLocalNotificationDateInterpretation — no incluir.
    await _plugin.zonedSchedule(
      notifId,
      title,
      body,
      tzFireAt,
      details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      // Requerido en versiones anteriores a v18 — usa la fecha/hora exacta
      // que pasamos (no interpreta como hora relativa al día).
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: eventId,
    );

    debugPrint('✅ ${type.name} programada (id=$notifId) para $fireAt');
  }

  Future<void> cancel(String eventId, AlarmType type) async {
    if (!_initialized) await init();
    await _plugin.cancel(_notifId(eventId, type));
    debugPrint('🗑️ ${type.name} cancelada para $eventId');
  }

  Future<void> cancelAll(String eventId) async {
    await cancel(eventId, AlarmType.alarm);
    await cancel(eventId, AlarmType.notification);
  }

  // ── Detalles de notificación ───────────────────────────────────────────────

  NotificationDetails _alarmDetails() => const NotificationDetails(
    android: AndroidNotificationDetails(
      _alarmChannelId,
      _alarmChannelName,
      channelDescription: 'Alarmas programadas para eventos',
      importance: Importance.max,
      priority: Priority.max,
      playSound: true,
      enableVibration: true,
      fullScreenIntent: true,
      category: AndroidNotificationCategory.alarm,
      visibility: NotificationVisibility.public,
    ),
    iOS: DarwinNotificationDetails(
      sound: 'default',
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      interruptionLevel: InterruptionLevel.timeSensitive,
    ),
  );

  NotificationDetails _notifDetails() => const NotificationDetails(
    android: AndroidNotificationDetails(
      _notifChannelId,
      _notifChannelName,
      channelDescription: 'Recordatorios de eventos del calendario',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      category: AndroidNotificationCategory.reminder,
      visibility: NotificationVisibility.private,
    ),
    iOS: DarwinNotificationDetails(
      sound: 'default',
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      interruptionLevel: InterruptionLevel.active,
    ),
  );

  // ── Helpers ────────────────────────────────────────────────────────────────

  int _notifId(String eventId, AlarmType type) {
    final base = eventId.hashCode.abs() % 500000000;
    return type == AlarmType.alarm ? base : base + 500000000;
  }
}
