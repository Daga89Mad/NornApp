// lib/views/premium/banner_ad_widget.dart
//
// Banner adaptativo anclado. Uso típico:
//
//   Scaffold(
//     ...
//     bottomNavigationBar: const BannerAdWidget(),
//   )
//
// Se oculta solo (sin dejar hueco) si el usuario es Premium, si no dio
// consentimiento para anuncios o si el anuncio no carga.
//
// NO usar en: diario, categorías de salud (periodo / bebé), login ni ajustes.

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../core/monetization/ad_config.dart';
import '../../core/monetization/consent_service.dart';
import '../../core/monetization/premium_service.dart';
import 'paywall_screen.dart';

class BannerAdWidget extends StatefulWidget {
  const BannerAdWidget({super.key, this.showRemoveAdsLink = true});

  /// Muestra debajo un enlace discreto "Quitar anuncios".
  final bool showRemoveAdsLink;

  @override
  State<BannerAdWidget> createState() => _BannerAdWidgetState();
}

class _BannerAdWidgetState extends State<BannerAdWidget> {
  BannerAd? _ad; // anuncio cargado y visible
  BannerAd? _loadingAd; // anuncio en carga (para poder liberarlo)
  AdSize? _size;
  int? _loadedForWidth;

  final _premium = PremiumService.instance.isPremium;
  final _adsReady = ConsentService.instance.adsReady;

  bool get _shouldShow =>
      AdConfig.isSupported && !_premium.value && _adsReady.value;

  @override
  void initState() {
    super.initState();
    _premium.addListener(_onStateChanged);
    _adsReady.addListener(_onStateChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _maybeLoad();
  }

  @override
  void dispose() {
    _premium.removeListener(_onStateChanged);
    _adsReady.removeListener(_onStateChanged);
    _ad?.dispose();
    _loadingAd?.dispose();
    super.dispose();
  }

  void _onStateChanged() {
    if (!mounted) return;
    if (!_shouldShow) {
      // Se hizo premium o retiró el consentimiento: fuera anuncio.
      _ad?.dispose();
      _loadingAd?.dispose();
      _ad = null;
      _loadingAd = null;
      _loadedForWidth = null;
    }
    setState(() {});
    _maybeLoad();
  }

  Future<void> _maybeLoad() async {
    if (!_shouldShow || _loadingAd != null) return;

    final width = MediaQuery.sizeOf(context).width.truncate();
    if (_ad != null && _loadedForWidth == width) return;

    final size = await AdSize.getLargeAnchoredAdaptiveBannerAdSize(width);
    if (!mounted || size == null || !_shouldShow) return;

    final ad = BannerAd(
      adUnitId: AdConfig.bannerUnitId,
      size: size,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (Ad loaded) {
          if (!mounted) {
            loaded.dispose();
            return;
          }
          setState(() {
            _ad?.dispose();
            _ad = loaded as BannerAd;
            _size = size;
            _loadedForWidth = width;
            _loadingAd = null;
          });
        },
        onAdFailedToLoad: (Ad failed, LoadAdError error) {
          debugPrint('⚠️ Banner no cargado: ${error.code} ${error.message}');
          failed.dispose();
          _loadingAd = null;
        },
      ),
    );
    _loadingAd = ad;
    await ad.load();
  }

  void _openPaywall() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const PaywallScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final ad = _ad;
    final size = _size;
    if (!_shouldShow || ad == null || size == null) {
      return const SizedBox.shrink();
    }

    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: size.width.toDouble(),
            height: size.height.toDouble(),
            child: AdWidget(ad: ad),
          ),
          if (widget.showRemoveAdsLink)
            InkWell(
              onTap: _openPaywall,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  'Quitar anuncios con Premium',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.primary,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
