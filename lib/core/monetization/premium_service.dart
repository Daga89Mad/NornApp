// lib/core/monetization/premium_service.dart
//
// Suscripción "NornApp Premium" con las compras nativas de cada tienda
// (StoreKit en iOS, Google Play Billing en Android). Es obligatorio usarlas
// para vender contenido digital: no se puede cobrar con Stripe/PayPal.
//
// Productos que debes crear con EXACTAMENTE estos IDs:
//   · App Store Connect → Suscripciones → grupo "NornApp Premium"
//   · Play Console → Monetizar → Suscripciones
//
// Hay tres formas de tener Premium:
//   1. COMPRA: al comprar o restaurar, la tienda confirma → premium durante un
//      margen de [_graceDays] días guardado en local. En cada arranque se
//      restauran las compras en silencio: si la suscripción sigue activa, el
//      margen se renueva; si la canceló, caduca solo.
//   2. CONCESIÓN MANUAL: un documento en la colección 'premium_grants' de
//      Firestore, cuyo ID es el correo del usuario en minúsculas. Sirve para
//      regalar la versión sin anuncios a personas concretas (familia, testers,
//      colaboradores) sin publicar nada. Solo tú escribes ahí desde la consola.
//   3. PRUEBAS: un interruptor local que solo funciona en compilaciones debug.
//
// LIMITACIÓN: sin servidor, la validación es solo en el dispositivo. Para una
// app en crecimiento conviene validar los recibos en una Cloud Function (o
// usar un servicio como RevenueCat). Para empezar es suficiente: lo único que
// desbloquea premium es quitar anuncios en el propio móvil.

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ad_config.dart';

class PremiumService {
  PremiumService._();
  static final PremiumService instance = PremiumService._();

  // ── IDs de producto (deben coincidir en ambas tiendas) ────────────────────
  static const String monthlyId = 'nornapp_premium_mensual';
  static const String yearlyId = 'nornapp_premium_anual';
  static const Set<String> productIds = {monthlyId, yearlyId};

  static const String _kPremiumUntil = 'premium_until_ms';
  static const String _kGrantCached = 'premium_grant_cached';
  static const String _kDebugPremium = 'debug_premium';
  static const int _graceDays = 3;

  /// Colección de concesiones manuales (ID del documento = correo en minúsculas)
  static const String grantsCollection = 'premium_grants';

  final InAppPurchase _iap = InAppPurchase.instance;

  /// ¿El usuario tiene premium activo? (escuchar desde la UI)
  final ValueNotifier<bool> isPremium = ValueNotifier<bool>(false);

  /// Productos cargados de la tienda, ordenados: mensual, anual.
  final ValueNotifier<List<ProductDetails>> products =
      ValueNotifier<List<ProductDetails>>(const []);

  /// Hay una compra en curso (para deshabilitar botones).
  final ValueNotifier<bool> purchasePending = ValueNotifier<bool>(false);

  /// Último error legible para mostrar en la pantalla de premium.
  final ValueNotifier<String?> lastError = ValueNotifier<String?>(null);

  StreamSubscription<List<PurchaseDetails>>? _sub;
  bool storeAvailable = false;

  /// El Premium actual viene de una concesión manual, no de una compra.
  bool isGranted = false;

  // ══════════════════════════════════════════════════════════════════════════
  // INIT
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> init() async {
    if (_sub != null || !AdConfig.isSupported) return;

    final prefs = await SharedPreferences.getInstance();

    // ── 3. Interruptor de PRUEBAS (solo debug) ──
    if (!kReleaseMode && (prefs.getBool(_kDebugPremium) ?? false)) {
      isPremium.value = true;
      debugPrint('🧪 Premium simulado (modo depuración)');
      return;
    }

    // ── Estado guardado: compra reciente o concesión ya conocida ──
    final until = prefs.getInt(_kPremiumUntil) ?? 0;
    final cachedGrant = prefs.getBool(_kGrantCached) ?? false;
    isGranted = cachedGrant;
    isPremium.value =
        cachedGrant || DateTime.now().millisecondsSinceEpoch < until;

    // ── 2. Concesión manual (Firestore) ──
    await refreshGrant();
    if (isGranted) return; // no hace falta molestar a la tienda

    // ── 1. Compra ──
    _sub = _iap.purchaseStream.listen(
      _onPurchaseUpdates,
      onError: (Object e) => debugPrint('❌ purchaseStream: $e'),
    );

    storeAvailable = await _iap.isAvailable();
    if (!storeAvailable) {
      debugPrint('⚠️ Tienda no disponible');
      return;
    }

    await loadProducts();

    try {
      await _iap.restorePurchases();
    } catch (e) {
      debugPrint('⚠️ restore silencioso: $e');
    }
  }

  /// Consulta si este usuario tiene Premium concedido manualmente.
  /// Se llama al arrancar y después de iniciar sesión.
  Future<void> refreshGrant() async {
    final email = FirebaseAuth.instance.currentUser?.email?.toLowerCase();
    if (email == null || email.isEmpty) return;

    try {
      final doc = await FirebaseFirestore.instance
          .collection(grantsCollection)
          .doc(email)
          .get();

      var granted = false;
      if (doc.exists) {
        final data = doc.data() ?? const <String, dynamic>{};
        final active = data['granted'] != false; // por defecto, concedido
        final until = data['until'];
        final vigente =
            until is! Timestamp || until.toDate().isAfter(DateTime.now());
        granted = active && vigente;
      }

      isGranted = granted;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kGrantCached, granted);

      if (granted) {
        isPremium.value = true;
        debugPrint('🎁 Premium concedido a $email');
      } else if (!granted && (prefs.getInt(_kPremiumUntil) ?? 0) <
          DateTime.now().millisecondsSinceEpoch) {
        // Se retiró la concesión y no hay compra vigente
        isPremium.value = false;
      }
    } catch (e) {
      // Sin conexión o sin permisos: se mantiene lo que hubiera en caché.
      debugPrint('⚠️ premium_grants: $e');
    }
  }

  /// Solo pruebas: activa o desactiva Premium sin comprar nada.
  Future<void> setDebugPremium(bool value) async {
    if (kReleaseMode) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kDebugPremium, value);
    isPremium.value = value;
  }

  Future<void> loadProducts() async {
    final response = await _iap.queryProductDetails(productIds);
    if (response.error != null) {
      debugPrint('❌ Productos: ${response.error}');
    }
    if (response.notFoundIDs.isNotEmpty) {
      debugPrint('⚠️ Productos no encontrados: ${response.notFoundIDs}');
    }

    // En Android puede llegar un ProductDetails por cada oferta: nos quedamos
    // con el primero de cada ID (el plan base).
    final byId = <String, ProductDetails>{};
    for (final p in response.productDetails) {
      byId.putIfAbsent(p.id, () => p);
    }
    products.value = [
      if (byId[monthlyId] != null) byId[monthlyId]!,
      if (byId[yearlyId] != null) byId[yearlyId]!,
    ];
  }

  // ══════════════════════════════════════════════════════════════════════════
  // ACCIONES
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> buy(ProductDetails product) async {
    lastError.value = null;
    purchasePending.value = true;
    try {
      // Las suscripciones se compran como "no consumibles".
      final ok = await _iap.buyNonConsumable(
        purchaseParam: PurchaseParam(productDetails: product),
      );
      if (!ok) purchasePending.value = false;
    } catch (e) {
      purchasePending.value = false;
      lastError.value = 'No se pudo iniciar la compra. Inténtalo de nuevo.';
      debugPrint('❌ buy: $e');
    }
  }

  /// Botón "Restaurar compras" (obligatorio en iOS).
  Future<void> restore() async {
    lastError.value = null;
    try {
      await _iap.restorePurchases();
    } catch (e) {
      lastError.value = 'No se pudieron restaurar las compras.';
      debugPrint('❌ restore: $e');
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // RESPUESTAS DE LA TIENDA
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> _onPurchaseUpdates(List<PurchaseDetails> purchases) async {
    for (final p in purchases) {
      switch (p.status) {
        case PurchaseStatus.pending:
          purchasePending.value = true;
          break;

        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          if (productIds.contains(p.productID)) {
            await _grantPremium();
          }
          purchasePending.value = false;
          break;

        case PurchaseStatus.error:
          purchasePending.value = false;
          lastError.value = 'La compra no se ha completado.';
          debugPrint('❌ Compra: ${p.error}');
          break;

        case PurchaseStatus.canceled:
          purchasePending.value = false;
          break;
      }

      // Obligatorio: si no se completa, Google Play reembolsa la compra a
      // los 3 días y StoreKit la vuelve a entregar en cada arranque.
      if (p.pendingCompletePurchase) {
        try {
          await _iap.completePurchase(p);
        } catch (e) {
          debugPrint('❌ completePurchase: $e');
        }
      }
    }
  }

  Future<void> _grantPremium() async {
    final until = DateTime.now()
        .add(const Duration(days: _graceDays))
        .millisecondsSinceEpoch;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kPremiumUntil, until);
    isPremium.value = true;
    debugPrint('⭐ Premium activo');
  }
}
