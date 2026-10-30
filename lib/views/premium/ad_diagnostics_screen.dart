// lib/views/premium/ad_diagnostics_screen.dart
//
// Diagnóstico de anuncios (Ajustes → Diagnóstico de anuncios).
// Enseña en el propio móvil por qué no aparece el banner: en las versiones de
// TestFlight / Play no hay logs, así que sin esto es imposible saberlo.
// Incluye un banner de prueba con el bloque REAL (no pulsar el anuncio).

import 'dart:io' show Platform;

import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../core/monetization/ad_config.dart';
import '../../core/monetization/consent_service.dart';
import '../../core/monetization/premium_service.dart';
import 'banner_ad_widget.dart';

class AdDiagnosticsScreen extends StatefulWidget {
  const AdDiagnosticsScreen({super.key});

  @override
  State<AdDiagnosticsScreen> createState() => _AdDiagnosticsScreenState();
}

class _AdDiagnosticsScreenState extends State<AdDiagnosticsScreen> {
  List<MapEntry<String, String>> _rows = const [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final consent = ConsentService.instance;
    final premium = PremiumService.instance;

    String consentStatus = '?';
    String canRequest = '?';
    String att = 'No aplica';
    try {
      consentStatus = (await ConsentInformation.instance.getConsentStatus())
          .name;
      canRequest = (await ConsentInformation.instance.canRequestAds())
          ? 'Sí'
          : 'NO';
    } catch (e) {
      consentStatus = 'Error: $e';
    }
    if (AdConfig.isSupported && Platform.isIOS) {
      try {
        att = (await AppTrackingTransparency.trackingAuthorizationStatus).name;
      } catch (e) {
        att = 'Error: $e';
      }
    }

    if (!mounted) return;
    setState(() {
      _rows = [
        MapEntry(
          'Plataforma',
          AdConfig.isSupported ? Platform.operatingSystem : 'No soportada',
        ),
        MapEntry(
          'Compilación',
          kReleaseMode ? 'Release (anuncios reales)' : 'Debug (anuncios de prueba)',
        ),
        MapEntry('Bloque de anuncios', AdConfig.bannerUnitId),
        MapEntry(
          'Premium',
          premium.isPremium.value
              ? 'SÍ${premium.isGranted ? " (concesión en premium_grants)" : " (compra)"} → sin anuncios'
              : 'No',
        ),
        MapEntry('Arranque', consent.startupStep.value),
        MapEntry('Consentimiento (UMP)', consentStatus),
        MapEntry('¿Puede pedir anuncios?', canRequest),
        MapEntry(
          'Opciones de privacidad',
          consent.privacyOptionsRequired.value ? 'Obligatorias (UE)' : 'No',
        ),
        MapEntry('Error de consentimiento', consent.lastConsentError ?? '—'),
        MapEntry('Seguimiento (ATT)', att),
        MapEntry('SDK listo', consent.adsReady.value ? 'Sí' : 'NO'),
        MapEntry(
          'Último banner',
          consent.lastBannerResult.value ?? 'Aún no se ha pedido ninguno',
        ),
      ];
    });
  }

  Future<void> _resetConsent() async {
    setState(() => _busy = true);
    try {
      await ConsentService.instance.resetConsentForTesting();
    } finally {
      if (mounted) setState(() => _busy = false);
      await _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Diagnóstico de anuncios'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          for (final r in _rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 150,
                    child: Text(
                      r.key,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Expanded(child: SelectableText(r.value)),
                ],
              ),
            ),
          const Divider(height: 28),
          const Text(
            'Banner de prueba (bloque real: no lo pulses). Si no aparece, '
            'pulsa Actualizar y mira "Último banner".',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          const BannerAdWidget(showRemoveAdsLink: false),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _busy ? null : _resetConsent,
            icon: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.restart_alt),
            label: const Text('Volver a pedir el consentimiento'),
          ),
        ],
      ),
    );
  }
}
