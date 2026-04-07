// lib/core/push_notification_service.dart
//
// Gestiona Firebase Cloud Messaging (FCM):
// - Solicita permisos iOS/Android
// - Obtiene y renueva el token FCM
// - Guarda el token en Firestore bajo user_profiles/{uid}
// - Muestra notificaciones FCM en foreground con flutter_local_notifications
// - Maneja tap en notificación (background / terminated)

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

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
  final FlutterLocalNotificationsPlugin _localPlugin =
      FlutterLocalNotificationsPlugin();

  static const _fcmChannelId = 'fc_push';
  static const _fcmChannelName = 'Eventos compartidos';

  bool _initialized = false;

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

    // 3. Inicializar plugin local para mostrar notificaciones en foreground
    await _localPlugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
    );

    // 4. Crear canal Android para FCM en foreground
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
    _fcm.onTokenRefresh.listen((token) => _saveTokenToFirestore(token));

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
    await _firestore.collection('user_profiles').doc(uid).set({
      'fcm_token': token,
      'token_updated': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    debugPrint('💾 FCM token guardado (uid=$uid)');
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
    if (uid != null) {
      try {
        await _firestore.collection('user_profiles').doc(uid).update({
          'fcm_token': FieldValue.delete(),
        });
      } catch (_) {}
    }
    try {
      await _fcm.deleteToken();
    } catch (_) {}
    debugPrint('🗑️ FCM token eliminado');
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
    // Aquí puedes añadir navegación cuando implementes el router global.
  }
}
