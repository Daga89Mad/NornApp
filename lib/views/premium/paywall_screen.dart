// lib/views/premium/paywall_screen.dart
//
// Pantalla de suscripción. Incluye lo que Apple revisa (guía 3.1.2):
//   · Nombre, duración y precio de cada plan (el precio lo da la tienda).
//   · Texto de renovación automática y cómo cancelar.
//   · Enlaces a Términos de uso (EULA) y Política de privacidad.
//   · Botón "Restaurar compras".
// No prometas aquí ventajas que la app aún no tenga: Apple lo rechaza.

import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/monetization/premium_service.dart';

class LegalLinks {
  LegalLinks._();

  /// ⚠️ Pon la URL real de tu política de privacidad (la misma que en las fichas).
  static const String privacyPolicy = 'https://TU-DOMINIO/privacidad';

  /// EULA estándar de Apple. Si tienes términos propios, pon su URL.
  static const String termsOfUse =
      'https://www.apple.com/legal/internet-services/itunes/dev/stdeula/';

  static String get manageSubscriptions => Platform.isIOS
      ? 'https://apps.apple.com/account/subscriptions'
      : 'https://play.google.com/store/account/subscriptions?package=com.yeahsoft.nornapp';

  static Future<void> open(String url) =>
      launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
}

class PaywallScreen extends StatefulWidget {
  const PaywallScreen({super.key});

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  final _premium = PremiumService.instance;
  String? _selectedId = PremiumService.yearlyId;

  @override
  void initState() {
    super.initState();
    if (_premium.products.value.isEmpty) _premium.loadProducts();
  }

  String _planName(ProductDetails p) =>
      p.id == PremiumService.yearlyId ? 'Anual' : 'Mensual';

  String _planPeriod(ProductDetails p) =>
      p.id == PremiumService.yearlyId ? 'al año' : 'al mes';

  Future<void> _restore() async {
    await _premium.restore();
    if (!mounted) return;
    final msg = _premium.isPremium.value
        ? 'Compras restauradas. ¡Ya eres Premium!'
        : 'No hemos encontrado ninguna suscripción activa.';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('NornApp Premium')),
      body: ValueListenableBuilder<bool>(
        valueListenable: _premium.isPremium,
        builder: (context, isPremium, _) {
          if (isPremium) return _buildAlreadyPremium(theme);
          return _buildOffer(theme);
        },
      ),
    );
  }

  // ── Ya es premium ──────────────────────────────────────────────────────────

  Widget _buildAlreadyPremium(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.workspace_premium, size: 72, color: Colors.amber),
            const SizedBox(height: 16),
            Text('Eres Premium', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 8),
            const Text(
              'Gracias por apoyar NornApp. Disfruta de la app sin anuncios.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: () => LegalLinks.open(LegalLinks.manageSubscriptions),
              child: const Text('Gestionar o cancelar suscripción'),
            ),
          ],
        ),
      ),
    );
  }

  // ── Oferta ─────────────────────────────────────────────────────────────────

  Widget _buildOffer(ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Icon(Icons.workspace_premium, size: 64, color: Colors.amber),
        const SizedBox(height: 12),
        Text(
          'Pásate a Premium',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall,
        ),
        const SizedBox(height: 20),
        const _Benefit(
          icon: Icons.block,
          text: 'Sin anuncios en toda la app',
        ),
        const _Benefit(
          icon: Icons.favorite_outline,
          text: 'Apoyas el desarrollo de nuevas funciones',
        ),
        const SizedBox(height: 20),

        // Planes
        ValueListenableBuilder<List<ProductDetails>>(
          valueListenable: _premium.products,
          builder: (context, products, _) {
            if (!_premium.storeAvailable && products.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'La tienda no está disponible ahora mismo. '
                  'Inténtalo más tarde.',
                  textAlign: TextAlign.center,
                ),
              );
            }
            if (products.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            return Column(
              children: products
                  .map(
                    (p) => Card(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: _selectedId == p.id
                              ? theme.colorScheme.primary
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: ListTile(
                        onTap: () => setState(() => _selectedId = p.id),
                        leading: Icon(
                          _selectedId == p.id
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                          color: theme.colorScheme.primary,
                        ),
                        title: Text(_planName(p)),
                        subtitle: Text('${p.price} ${_planPeriod(p)}'),
                      ),
                    ),
                  )
                  .toList(),
            );
          },
        ),
        const SizedBox(height: 16),

        // Botón comprar
        ValueListenableBuilder<bool>(
          valueListenable: _premium.purchasePending,
          builder: (context, pending, _) {
            final products = _premium.products.value;
            final selected = products
                .where((p) => p.id == _selectedId)
                .firstOrNull;
            return ElevatedButton(
              onPressed: pending || selected == null
                  ? null
                  : () => _premium.buy(selected),
              child: pending
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Suscribirme'),
            );
          },
        ),

        // Error
        ValueListenableBuilder<String?>(
          valueListenable: _premium.lastError,
          builder: (context, error, _) => error == null
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    error,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
        ),

        TextButton(
          onPressed: _restore,
          child: const Text('Restaurar compras'),
        ),
        const SizedBox(height: 8),

        // Texto legal obligatorio
        Text(
          'La suscripción se renueva automáticamente al final de cada periodo '
          'salvo que la canceles al menos 24 horas antes. El pago se cargará '
          'en tu cuenta de ${Platform.isIOS ? 'Apple' : 'Google Play'} al '
          'confirmar la compra. Puedes gestionarla o cancelarla en cualquier '
          'momento desde los ajustes de tu cuenta de la tienda.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.center,
          children: [
            TextButton(
              onPressed: () => LegalLinks.open(LegalLinks.termsOfUse),
              child: const Text('Términos de uso'),
            ),
            TextButton(
              onPressed: () => LegalLinks.open(LegalLinks.privacyPolicy),
              child: const Text('Política de privacidad'),
            ),
          ],
        ),
      ],
    );
  }
}

class _Benefit extends StatelessWidget {
  const _Benefit({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
