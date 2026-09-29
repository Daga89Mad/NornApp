// lib/core/push_notification_service.dart
//
// Gestiona Firebase Cloud Messaging (FCM):
// - Solicita permisos iOS/Android
// - Obtiene y renueva el token FCM
// - Guarda el token en Firestore bajo user_profiles/{uid}.fcm_tokens (ARRAY,
//   multi-dispositivo). Las Cloud Functions (notifyTaskCreated,
//   notifyFriendRequest, notifyDateChange…) leen ese array para enviar push.
// - Muestra notificaciones FCM en foreground con flutter_local_notifications
// - Maneja tap en notificación (background / terminated)
//
// CAMBIO respecto a la versión anterior: antes se guardaba un único
// `fcm_token` (string). Ahora se usa `fcm_tokens` (array) con arrayUnion /
// arrayRemove, para soportar varios dispositivos por usuario y permitir que el
// backend pode tokens inválidos. La Function sigue leyendo el `fcm_token`
// antiguo como fallback, así que la migración es transparente.
//
// NUEVO:
// - Notificaciones "sociales" (data.type = 'friend_request' | 'date_change'):
//   al pulsarlas se abre la pantalla correspondiente (ver onOpenFromPush, lo
//   registra MenuScreen). Si la app estaba cerrada, se guarda y se abre en
//   cuanto hay pantalla (takePendingOpen).
// - En iOS ya no se duplica la notificación con la app abierta: iOS la
//   muestra solo (setForegroundNotificationPresentationOptions) y antes
//   además se lanzaba otra local.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
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

  /// Tipos de notificación que abren una pantalla al pulsarlas.
  static const Set<String> _socialTypes = {'friend_request', 'date_change'};

  bool _initialized = false;

  // Último token conocido; necesario para poder darlo de baja en logout.
  String? _lastToken;

  /// La app decide cómo abrir un evento al pulsar una notificación. Recibe el
  /// eventId del payload de datos. Asígnalo desde donde tengas el router global.
  void Function(String eventId)? onOpenEvent;

  /// Qué hacer al pulsar una notificación de solicitud de amistad o de cambio
  /// de día. Recibe el 'data' del mensaje. Lo registra MenuScreen.
  void Function(Map<String, dynamic> data)? onOpenFromPush;

  /// Notificación pulsada cuando aún no había pantalla para atenderla
  /// (app cerrada del todo, o sin sesión iniciada todavía).
  Map<String, dynamic>? _pendingOpen;

  /// Devuelve (una sola vez) la notificación pulsada pendiente de abrir.
  Map<String, dynamic>? takePendingOpen() {
    final p = _pendingOpen;
    _pendingOpen = null;
    return p;
  }

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
    //    OJO: el channelId debe coincidir con el que envían las Cloud
    //    Functions (ANDROID_CHANNEL_ID = 'fc_push').
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

    // 6. Escuchar mensajes en foreground → notificación local (Android)
    FirebaseMessaging.onMessage.listen(_onForegroundMessage);

    // 7. Tap desde background
    FirebaseMessaging.onMessageOpenedApp.listen(_onMessageTap);

    // 8. App abierta desde notificación (terminated)
    final initial = await _fcm.getInitialMessage();
    if (initial != null) _onMessageTap(initial);

    // 9. Auto-renovar token. Se escucha ANTES de pedirlo: en iPhone el token
    //    FCM suele llegar por aquí unos segundos después de arrancar.
    _fcm.onTokenRefresh.listen((t) async {
      try {
        await _saveTokenToFirestore(t);
      } catch (e) {
        debugPrint('Error guardando FCM token renovado: $e');
      }
    });

    // 10. Token del usuario con sesión: al arrancar (también si la sesión se
    //     restauró sola, sin pasar por el login) y en cada login.
    //     Sin await: en iPhone puede tardar unos segundos y no debe retrasar
    //     el arranque de la app.
    FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null) _refreshAndSaveToken();
    });

    _initialized = true;
    debugPrint('✅ PushNotificationService inicializado');
  }

  // ── Token ──────────────────────────────────────────────────────────────────

  Future<void>? _refreshing;

  /// Obtiene el token FCM y lo guarda en el perfil del usuario.
  /// Si ya hay una petición en marcha, reutiliza esa.
  Future<void> _refreshAndSaveToken() {
    return _refreshing ??= _doRefreshAndSaveToken().whenComplete(
      () => _refreshing = null,
    );
  }

  Future<void> _doRefreshAndSaveToken() async {
    if (FirebaseAuth.instance.currentUser == null) return;
    try {
      final token = await _getFcmToken();
      if (token != null) await _saveTokenToFirestore(token);
    } catch (e) {
      debugPrint('Error obteniendo FCM token: $e');
    }
  }

  /// CORREGIDO (iPhone sin notificaciones): en iOS el token FCM depende del
  /// token APNs, que Apple entrega unos instantes DESPUÉS de registrarse.
  /// Pedir el token FCM antes lanza 'apns-token-not-set'; antes ese error se
  /// tragaba en silencio y el iPhone se quedaba sin token guardado, así que
  /// las Cloud Functions no tenían a quién enviar.
  Future<String?> _getFcmToken() async {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      String? apns = await _fcm.getAPNSToken();
      for (var i = 0; apns == null && i < 15; i++) {
        await Future.delayed(const Duration(seconds: 1));
        apns = await _fcm.getAPNSToken();
      }
      if (apns == null) {
        // Suele ser: falta la capacidad "Push Notifications" en Xcode, el
        // usuario no dio permiso, o es el simulador.
        debugPrint('⚠️ iOS sin token APNs: no se puede obtener token FCM');
        return null;
      }
    }
    return _fcm.getToken();
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
  /// No espera a que termine (en iPhone puede tardar unos segundos).
  Future<void> onUserLoggedIn() async {
    if (!_initialized) await init();
    _refreshAndSaveToken();
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
    _pendingOpen = null;
    debugPrint('🗑️ FCM token dado de baja');
  }

  // ── Handlers ───────────────────────────────────────────────────────────────

  Future<void> _onForegroundMessage(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;

    // iOS ya la muestra solo con la app abierta (paso 5 de init). Lanzar
    // además una local hacía que llegara DUPLICADA.
    if (defaultTargetPlatform == TargetPlatform.iOS) return;

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

    // Solicitud de amistad / cambio de día → abrir su pantalla.
    final type = message.data['type'] as String?;
    if (type != null && _socialTypes.contains(type)) {
      final data = Map<String, dynamic>.from(message.data);
      final handler = onOpenFromPush;
      if (handler != null) {
        handler(data);
      } else {
        _pendingOpen = data; // se abrirá cuando MenuScreen esté lista
      }
      return;
    }

    final eventId = message.data['eventId'] as String?;
    if (eventId != null && eventId.isNotEmpty) {
      onOpenEvent?.call(eventId);
    }
  }
}
