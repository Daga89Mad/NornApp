// lib/core/monetization/consent_service.dart
//
// Orden obligatorio antes de pedir anuncios:
//   1. Consentimiento RGPD con UMP (Google lo exige en el EEE / Reino Unido).
//   2. En iOS, aviso de App Tracking Transparency (ATT) para personalizar.
//   3. Inicializar el SDK de AdMob, solo si canRequestAds() == true.
//
// IMPORTANTE (AdMob → Privacidad y mensajes): crea y publica el mensaje
// "RGPD", pero NO actives el "mensaje explicativo de IDFA": el aviso ATT lo
// lanza esta clase. Si activas los dos, iOS mostraría dos avisos seguidos.

import 'dart:async';
import 'dart:io' show Platform;

import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'ad_config.dart';

class ConsentService {
  ConsentService._();
  static final ConsentService instance = ConsentService._();

  /// true cuando el SDK está inicializado y se pueden pedir anuncios.
  final ValueNotifier<bool> adsReady = ValueNotifier<bool>(false);

  /// true si el usuario está en una región donde hay que ofrecer
  /// "Opciones de privacidad" para cambiar su consentimiento (obligatorio).
  final ValueNotifier<bool> privacyOptionsRequired = ValueNotifier<bool>(
    false,
  );

  bool _started = false;
  bool _sdkInitialized = false;

  // ══════════════════════════════════════════════════════════════════════════
  // ARRANQUE
  // ══════════════════════════════════════════════════════════════════════════

  /// Llamar una vez, con la app ya en pantalla (post-frame).
  Future<void> gatherConsentAndInitAds() async {
    if (_started || !AdConfig.isSupported) return;
    _started = true;

    // 1. Consentimiento RGPD
    await _requestConsentUpdateAndShowFormIfRequired();

    // 2. ATT (solo iOS)
    await _requestTrackingAuthorizationIfNeeded();

    // 3. Estado + SDK
    await _refreshConsentState();
    if (await ConsentInformation.instance.canRequestAds()) {
      await _initializeSdk();
    }
  }

  Future<void> _requestConsentUpdateAndShowFormIfRequired() async {
    final completer = Completer<void>();
    void done() {
      if (!completer.isCompleted) completer.complete();
    }

    final params = ConsentRequestParameters(
      // En debug se simula estar en la UE para poder probar el formulario.
      consentDebugSettings: kDebugMode
          ? ConsentDebugSettings(
              debugGeography: DebugGeography.debugGeographyEea,
              testIdentifiers: AdConfig.testDeviceIds,
            )
          : null,
    );

    ConsentInformation.instance.requestConsentInfoUpdate(
      params,
      () {
        ConsentForm.loadAndShowConsentFormIfRequired((FormError? error) {
          if (error != null) {
            debugPrint('⚠️ UMP formulario: ${error.message}');
          }
          done();
        });
      },
      (FormError error) {
        // Sin conexión, etc. Puede haber consentimiento de una sesión previa.
        debugPrint('⚠️ UMP update: ${error.message}');
        done();
      },
    );

    await completer.future;
  }

  Future<void> _requestTrackingAuthorizationIfNeeded() async {
    if (!Platform.isIOS) return;
    try {
      final status = await AppTrackingTransparency.trackingAuthorizationStatus;
      if (status == TrackingStatus.notDetermined) {
        // iOS ignora la petición si la app aún no está activa del todo.
        await Future<void>.delayed(const Duration(milliseconds: 400));
        await AppTrackingTransparency.requestTrackingAuthorization();
      }
    } catch (e) {
      debugPrint('⚠️ ATT: $e');
    }
  }

  Future<void> _refreshConsentState() async {
    try {
      final status = await ConsentInformation.instance
          .getPrivacyOptionsRequirementStatus();
      privacyOptionsRequired.value =
          status == PrivacyOptionsRequirementStatus.required;
    } catch (_) {
      privacyOptionsRequired.value = false;
    }
  }

  Future<void> _initializeSdk() async {
    if (_sdkInitialized) {
      adsReady.value = true;
      return;
    }
    _sdkInitialized = true;
    await MobileAds.instance.updateRequestConfiguration(
      RequestConfiguration(testDeviceIds: AdConfig.testDeviceIds),
    );
    await MobileAds.instance.initialize();
    adsReady.value = true;
    debugPrint('✅ AdMob inicializado');
  }

  // ══════════════════════════════════════════════════════════════════════════
  // OPCIONES DE PRIVACIDAD (botón en Ajustes)
  // ══════════════════════════════════════════════════════════════════════════

  /// Vuelve a mostrar el formulario para que el usuario cambie su elección.
  Future<void> showPrivacyOptionsForm() async {
    if (!AdConfig.isSupported) return;
    final completer = Completer<void>();
    ConsentForm.showPrivacyOptionsForm((FormError? error) {
      if (error != null) debugPrint('⚠️ UMP opciones: ${error.message}');
      if (!completer.isCompleted) completer.complete();
    });
    await completer.future;

    await _refreshConsentState();
    if (await ConsentInformation.instance.canRequestAds()) {
      await _initializeSdk();
    } else {
      adsReady.value = false;
    }
  }
}
