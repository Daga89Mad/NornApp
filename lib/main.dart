// lib/main.dart
import 'package:flutter/foundation.dart'
    show kIsWeb, kReleaseMode, defaultTargetPlatform, TargetPlatform, debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite/sqflite.dart';
import 'firebase_options.dart';
import 'core/alarm_service.dart';
import 'core/push_notification_service.dart';
import 'core/monetization/consent_service.dart';
import 'core/monetization/premium_service.dart';
import 'views/loginBody.dart';
import 'views/menu.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // SEGURIDAD: debugPrint SÍ escribe en el log del sistema en release
  // (Logcat / Consola de macOS). La app imprime uids, emails, rutas de la BD
  // y payloads de notificaciones, así que en release se silencia.
  if (kReleaseMode) {
    debugPrint = (String? message, {int? wrapWidth}) {};
  }

  // sqflite FFI para escritorio
  if (!kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.macOS)) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  // Firebase — primero siempre
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Alarmas locales
  await AlarmService.instance.init();

  // Push notifications FCM (registra el handler de background)
  await PushNotificationService.instance.init();

  runApp(const MyApp());

  // Monetización: con la app ya en pantalla (el formulario de consentimiento
  // y el aviso ATT de iOS necesitan una vista activa). No bloquea el arranque.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    PremiumService.instance.init();
    ConsentService.instance.gatherConsentAndInitAds();
  });
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NornApp',
      debugShowCheckedModeBanner: false,

      // ── Español fijo ─────────────────────────────────────────────────────
      // Con el locale es_ES, los calendarios nativos (showDatePicker) salen en
      // español y la semana empieza en LUNES (firstDayOfWeekIndex = 1). Sin
      // esto, Flutter usa en_US: cabeceras S M T W T F S y semana en domingo.
      locale: const Locale('es', 'ES'),
      supportedLocales: const [Locale('es', 'ES'), Locale('es'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],

      theme: ThemeData(
        brightness: Brightness.light,
        primarySwatch: Colors.blue,
        inputDecorationTheme: const InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 48),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ),
      darkTheme: ThemeData.light(),
      themeMode: ThemeMode.light,
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (ctx, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          return snapshot.hasData ? const MenuScreen() : const LoginBody();
        },
      ),
    );
  }
}
