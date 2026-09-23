// lib/core/monetization/ad_config.dart
//
// IDs de AdMob. En debug/profile se usan SIEMPRE los IDs de prueba de Google:
// hacer clic en tus propios anuncios reales puede suspender tu cuenta AdMob.
//
// ⚠️ Sustituye los valores 'ca-app-pub-XXXXXXXXXXXXXXXX/...' por los de tu
//    cuenta (AdMob → Apps → NornApp → Bloques de anuncios).
//    El App ID (con '~') NO va aquí: va en Info.plist y AndroidManifest.xml.

import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';

class AdConfig {
  AdConfig._();

  // ── Producción ────────────────────────────────────────────────────────────
  static const String _androidBannerProd =
      'ca-app-pub-XXXXXXXXXXXXXXXX/NNNNNNNNNN';
  static const String _iosBannerProd = 'ca-app-pub-XXXXXXXXXXXXXXXX/NNNNNNNNNN';

  // ── Prueba (IDs oficiales de Google) ──────────────────────────────────────
  static const String _androidBannerTest =
      'ca-app-pub-3940256099942544/9214589741';
  static const String _iosBannerTest = 'ca-app-pub-3940256099942544/2435281174';

  /// Hashes de tus móviles de prueba (aparecen en el log la primera vez que
  /// se pide un anuncio: "Use RequestConfiguration...setTestDeviceIds").
  static const List<String> testDeviceIds = <String>[];

  static String get bannerUnitId {
    final useTest = !kReleaseMode;
    if (Platform.isIOS) return useTest ? _iosBannerTest : _iosBannerProd;
    return useTest ? _androidBannerTest : _androidBannerProd;
  }

  /// Plataformas donde hay anuncios (en escritorio no existe el SDK).
  static bool get isSupported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);
}
