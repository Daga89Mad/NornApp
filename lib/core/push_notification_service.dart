// lib/core/push_notification_service.dart
//
// Gestiona Firebase Cloud Messaging (FCM):
// - Solicita permisos iOS/Android
// - Obtiene y renueva el token FCM
// - Guarda el token en Firestore bajo user_profiles/{uid}.fcm_tokens (ARRAY,
//   multi-dispositivo). La Cloud Function `notifyTaskCreated` lee ese array
//   para enviar la notificación de tarea compartida.
// - Muestra notificaciones FCM en foreground con flutter_local_notifications
// - Maneja tap en notificación (background / terminated)
//
// CAMBIO respecto a la versión anterior: antes se guardaba un único
// `fcm_token` (string). Ahora se usa `fcm_tokens` (array) con arrayUnion /
// arrayRemove, para soportar varios dispositivos por usuario y permitir que el
// backend pode tokens inválidos. La Function sigue leyendo el `fcm_token`
// antiguo como fallback, así que la migración es transparente.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'alarm_service.dart';

// Handler de mensajes en background/terminated.
// DEBE ser función top-level (fuera de cualquier clase).
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('📩 FCM background: ${message.notification?.title}');
}

class PushNotificationService {
  PushNotificationService._();
  static final PushNotificationService instance = PushNotificationService._();

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  // Usa la instancia compartida de AlarmService para evitar conflictos de canales
  FlutterLocalNotificationsPlugin get _localPlugin => AlarmService.plugin;

  static const _fcmChannelId = 'fc_push';
  static const _fcmChannelName = 'Eventos compartidos';

  bool _initialized = false;

  // Último token conocido; necesario para poder darlo de baja en logout.
  String? _lastToken;

  /// La app decide cómo abrir un evento al pulsar una notificación. Recibe el
  /// eventId del payload de datos. Asígnalo desde donde tengas el router global.
  void Function(String eventId)? onOpenEvent;

  // ── Init ───────────────────────────────────────────────────────────────────

  Future<void> init() async {
    if (_initialized) return;

    // 1. Registrar handler de background
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // 2. Pedir permisos (iOS obligatorio, Android 13+ recomendado)
    final settings = await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    debugPrint('FCM permisos: ${settings.authorizationStatus}');

    // 3. Asegurar que AlarmService está inicializado (crea los canales Android)
    await AlarmService.instance.init();

    // 4. Crear canal Android adicional para mensajes FCM en foreground.
    //    OJO: el channelId debe coincidir con el que envía la Cloud Function
    //    (notifyTaskCreated → ANDROID_CHANNEL_ID = 'fc_push').
    await _localPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            _fcmChannelId,
            _fcmChannelName,
            description: 'Notificaciones de eventos compartidos',
            importance: Importance.high,
          ),
        );

    // 5. Mostrar notificaciones FCM en foreground (iOS)
    await _fcm.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    // 6. Escuchar mensajes en foreground → notificación local
    FirebaseMessaging.onMessage.listen(_onForegroundMessage);

    // 7. Tap desde background
    FirebaseMessaging.onMessageOpenedApp.listen(_onMessageTap);

    // 8. App abierta desde notificación (terminated)
    final initial = await _fcm.getInitialMessage();
    if (initial != null) _onMessageTap(initial);

    // 9. Token inicial
    await _refreshAndSaveToken();

    // 10. Auto-renovar token
    _fcm.onTokenRefresh.listen(_saveTokenToFirestore);

    _initialized = true;
    debugPrint('✅ PushNotificationService inicializado');
  }

  // ── Token ──────────────────────────────────────────────────────────────────

  Future<void> _refreshAndSaveToken() async {
    try {
      final token = await _fcm.getToken();
      if (token != null) await _saveTokenToFirestore(token);
    } catch (e) {
      debugPrint('Error obteniendo FCM token: $e');
    }
  }

  Future<void> _saveTokenToFirestore(String token) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    _lastToken = token;
    await _firestore.collection('user_profiles').doc(uid).set({
      // arrayUnion es idempotente: no duplica si el token ya estaba.
      'fcm_tokens': FieldValue.arrayUnion([token]),
      'token_updated': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    debugPrint('💾 FCM token guardado en fcm_tokens (uid=$uid)');
  }

  // ── Llamar desde login / logout ────────────────────────────────────────────

  /// Llama esto justo después del login para asociar el token al usuario.
  Future<void> onUserLoggedIn() async {
    if (!_initialized) await init();
    await _refreshAndSaveToken();
  }

  /// Llama esto al hacer logout para que el dispositivo deje de recibir push.
  Future<void> onUserLoggedOut() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final token = _lastToken ?? await _fcm.getToken();
    if (uid != null && token != null) {
      try {
        await _firestore.collection('user_profiles').doc(uid).update({
          'fcm_tokens': FieldValue.arrayRemove([token]),
        });
      } catch (_) {}
    }
    try {
      await _fcm.deleteToken();
    } catch (_) {}
    _lastToken = null;
    debugPrint('🗑️ FCM token dado de baja');
  }

  // ── Handlers ───────────────────────────────────────────────────────────────

  Future<void> _onForegroundMessage(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;
    await _localPlugin.show(
      message.hashCode,
      notification.title,
      notification.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _fcmChannelId,
          _fcmChannelName,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: message.data['eventId'],
    );
  }

  void _onMessageTap(RemoteMessage message) {
    debugPrint('👆 Notificación pulsada: ${message.data}');
    final eventId = message.data['eventId'] as String?;
    if (eventId != null && eventId.isNotEmpty) {
      onOpenEvent?.call(eventId);
    }
  }
}
