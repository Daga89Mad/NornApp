// lib/core/alarm_service.dart
//
// flutter_local_notifications ^18.0.1 — sin flutter_timezone.
//
// TRUCO DE TIMEZONE SIN PAQUETE EXTRA:
//   Dart sabe la hora local del dispositivo nativamente.
//   fireAt.toUtc() convierte usando el offset del sistema operativo.
//   Luego creamos un TZDateTime en UTC → el scheduler dispara en el momento exacto.
//   Ejemplo: usuario en Madrid (UTC+2), alarma a las 14:00 local
//     → fireAt.toUtc() = 12:00 UTC → TZDateTime(UTC, 12:00) → suena a las 14:00 ✓

import 'dart:typed_data'; // Int64List para patrones de vibración

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

enum AlarmType { alarm, notification }

class AlarmService {
  AlarmService._();
  static final AlarmService instance = AlarmService._();

  /// Instancia compartida con PushNotificationService.
  static final FlutterLocalNotificationsPlugin plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  // ── IDs de canales ────────────────────────────────────────────────────────

  static const _alarmChannelId = 'nornapp_alarms';
  static const _alarmChannelName = 'Alarmas NornApp';
  static const _notifChannelId = 'nornapp_reminders';
  static const _notifChannelName = 'Recordatorios NornApp';

  // ── Inicialización ────────────────────────────────────────────────────────

  Future<void> init() async {
    if (_initialized) return;

    // Solo necesitamos registrar todas las zonas horarias del paquete timezone.
    // La conversión real la hace Dart con .toUtc() (usa el offset del SO).
    tz.initializeTimeZones();

    // Inicializar plugin
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    await plugin.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: _onTap,
      onDidReceiveBackgroundNotificationResponse: _onBackgroundTap,
    );

    // Canales Android (idempotente)
    final androidImpl = plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    await androidImpl?.createNotificationChannel(
      const AndroidNotificationChannel(
        _alarmChannelId,
        _alarmChannelName,
        description: 'Alarmas programadas de NornApp',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
        enableLights: true,
        ledColor: Color(0xFF5C6BC0),
      ),
    );

    await androidImpl?.createNotificationChannel(
      const AndroidNotificationChannel(
        _notifChannelId,
        _notifChannelName,
        description: 'Recordatorios de eventos de NornApp',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
      ),
    );

    // Permisos Android 13+
    await androidImpl?.requestNotificationsPermission();
    await androidImpl?.requestExactAlarmsPermission();

    _initialized = true;
    debugPrint('✅ AlarmService inicializado');
  }

  /// Pide permisos en iOS — llamar justo después del login.
  Future<bool> requestIosPermission() async {
    final iosImpl = plugin
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

  // ── Programar ─────────────────────────────────────────────────────────────

  Future<void> schedule({
    required String eventId,
    required String title,
    required String body,
    required DateTime fireAt,
    required AlarmType type,
  }) async {
    if (!_initialized) await init();

    // Convertir la hora local del usuario a UTC usando el offset del SO.
    // Si fireAt ya es UTC (.isUtc == true), .toUtc() no hace nada.
    // Si es local, .toUtc() aplica el offset del dispositivo correctamente.
    final utc = fireAt.toUtc();
    final tzFireAt = tz.TZDateTime.from(utc, tz.UTC);
    final tzNow = tz.TZDateTime.now(tz.UTC);

    if (tzFireAt.isBefore(tzNow)) {
      debugPrint('⚠️ Fecha en el pasado, ${type.name} no programada: $fireAt');
      return;
    }

    final notifId = _notifId(eventId, type);
    final details = type == AlarmType.alarm ? _alarmDetails() : _notifDetails();

    await plugin.zonedSchedule(
      notifId,
      title,
      body,
      tzFireAt,
      details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: eventId,
    );

    final diff = tzFireAt.difference(tzNow);
    debugPrint(
      '✅ ${type.name} programada id=$notifId '
      'local=$fireAt UTC=${utc.toIso8601String()} '
      '(en ${diff.inMinutes} min)',
    );
  }

  // ── Cancelar ──────────────────────────────────────────────────────────────

  Future<void> cancel(String eventId, AlarmType type) async {
    if (!_initialized) await init();
    await plugin.cancel(_notifId(eventId, type));
    debugPrint('🗑️ ${type.name} cancelada para $eventId');
  }

  Future<void> cancelAll(String eventId) async {
    await cancel(eventId, AlarmType.alarm);
    await cancel(eventId, AlarmType.notification);
  }

  // ── Detalles de notificación ──────────────────────────────────────────────

  NotificationDetails _alarmDetails() => NotificationDetails(
    android: AndroidNotificationDetails(
      _alarmChannelId,
      _alarmChannelName,
      channelDescription: 'Alarmas programadas de NornApp',
      importance: Importance.max,
      priority: Priority.max,
      playSound: true,
      enableVibration: true,
      // 0ms espera → vibra 800ms → pausa 400ms → vibra 800ms
      vibrationPattern: Int64List.fromList([0, 800, 400, 800]),
      // Muestra pantalla completa aunque el móvil esté bloqueado
      // Requiere USE_FULL_SCREEN_INTENT en AndroidManifest.xml
      fullScreenIntent: true,
      category: AndroidNotificationCategory.alarm,
      visibility: NotificationVisibility.public,
      // audioAttributesUsage.alarm: el sistema lo trata como despertador,
      // suena aunque el teléfono esté en modo silencio/vibración
      audioAttributesUsage: AudioAttributesUsage.alarm,
      autoCancel: true,
    ),
    iOS: const DarwinNotificationDetails(
      sound: 'default',
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      // timeSensitive rompe Focus Mode en iOS 15+
      interruptionLevel: InterruptionLevel.timeSensitive,
    ),
  );

  NotificationDetails _notifDetails() => NotificationDetails(
    android: AndroidNotificationDetails(
      _notifChannelId,
      _notifChannelName,
      channelDescription: 'Recordatorios de eventos de NornApp',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      // Vibración más suave para recordatorios
      vibrationPattern: Int64List.fromList([0, 300, 200, 300]),
      category: AndroidNotificationCategory.reminder,
      visibility: NotificationVisibility.private,
      autoCancel: true,
    ),
    iOS: const DarwinNotificationDetails(
      sound: 'default',
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      interruptionLevel: InterruptionLevel.active,
    ),
  );

  // ── Helpers ───────────────────────────────────────────────────────────────

  int _notifId(String eventId, AlarmType type) {
    final base = eventId.hashCode.abs() % 500000000;
    return type == AlarmType.alarm ? base : base + 500000000;
  }
}

// ── Callbacks top-level (flutter_local_notifications lo requiere así) ─────────

@pragma('vm:entry-point')
void _onTap(NotificationResponse r) {
  debugPrint('👆 Notificación pulsada id=${r.id} payload=${r.payload}');
}

@pragma('vm:entry-point')
void _onBackgroundTap(NotificationResponse r) {
  debugPrint('👆 Background tap id=${r.id}');
}
