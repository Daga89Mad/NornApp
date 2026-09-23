// lib/views/account_settings_screen.dart
//
// Pantalla "Ajustes" → cuenta del usuario.
// Incluye la ELIMINACIÓN DE CUENTA dentro de la app, obligatoria para
// publicar en App Store (guía 5.1.1(v)) y Google Play, el acceso a Premium
// y las "Opciones de privacidad" de anuncios (obligatorias con UMP en la UE).

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:nornapp/core/account_service.dart';
import 'package:nornapp/core/monetization/consent_service.dart';
import 'package:nornapp/core/monetization/premium_service.dart';
import 'package:nornapp/views/loginBody.dart';
import 'package:nornapp/views/premium/paywall_screen.dart';

class AccountSettingsScreen extends StatefulWidget {
  const AccountSettingsScreen({super.key});

  @override
  State<AccountSettingsScreen> createState() => _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends State<AccountSettingsScreen> {
  bool _busy = false;

  User? get _user => FirebaseAuth.instance.currentUser;

  // ── Acciones ───────────────────────────────────────────────────────────────

  Future<void> _signOut() async {
    setState(() => _busy = true);
    await AccountService.instance.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginBody()),
      (route) => false,
    );
  }

  Future<void> _sendPasswordReset() async {
    final email = _user?.email;
    if (email == null) return;
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      _snack('Te hemos enviado un correo para cambiar la contraseña.');
    } catch (_) {
      _snack('No se pudo enviar el correo. Inténtalo más tarde.', error: true);
    }
  }

  Future<void> _deleteAccount() async {
    // 1. Confirmación explícita
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar cuenta'),
        content: const Text(
          'Se borrarán de forma permanente tu cuenta, tus eventos, turnos, '
          'menús, tareas, entrenamientos, amigos, la copia de tu diario y '
          'todo lo que has compartido.\n\nEsta acción no se puede deshacer.'
          '\n\nSi tienes NornApp Premium, borrar la cuenta NO cancela la '
          'suscripción: cancélala en los ajustes de tu cuenta de la tienda.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Continuar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    // 2. Contraseña (Firebase exige un login reciente para borrar la cuenta)
    final password = await _askPassword();
    if (password == null || password.isEmpty || !mounted) return;

    setState(() => _busy = true);
    final result = await AccountService.instance.deleteAccount(
      password: password,
    );
    if (!mounted) return;
    setState(() => _busy = false);

    switch (result) {
      case DeleteAccountResult.ok:
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginBody()),
          (route) => false,
        );
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tu cuenta se ha eliminado.')),
        );
        break;
      case DeleteAccountResult.wrongPassword:
        _snack('Contraseña incorrecta.', error: true);
        break;
      case DeleteAccountResult.requiresRecentLogin:
        _snack(
          'Por seguridad, cierra sesión, vuelve a entrar e inténtalo de nuevo.',
          error: true,
        );
        break;
      case DeleteAccountResult.error:
        _snack(
          'No se pudo eliminar la cuenta. Revisa tu conexión e inténtalo de nuevo.',
          error: true,
        );
        break;
    }
  }

  Future<String?> _askPassword() {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirma tu contraseña'),
        content: TextField(
          controller: ctrl,
          obscureText: true,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Contraseña'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Eliminar definitivamente'),
          ),
        ],
      ),
    ).whenComplete(ctrl.dispose);
  }

  void _openPaywall() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const PaywallScreen()));
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? Colors.red.shade600 : null,
      ),
    );
  }

  // ── UI ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final user = _user;
    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes')),
      body: AbsorbPointer(
        absorbing: _busy,
        child: Stack(
          children: [
            ListView(
              children: [
                ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: Text(user?.displayName ?? 'Mi cuenta'),
                  subtitle: Text(user?.email ?? ''),
                ),
                const Divider(),

                // ── Premium ────────────────────────────────────────────────
                ValueListenableBuilder<bool>(
                  valueListenable: PremiumService.instance.isPremium,
                  builder: (context, isPremium, _) => ListTile(
                    leading: const Icon(
                      Icons.workspace_premium,
                      color: Colors.amber,
                    ),
                    title: Text(isPremium ? 'Eres Premium' : 'NornApp Premium'),
                    subtitle: Text(
                      isPremium
                          ? 'Gestionar suscripción'
                          : 'Quita los anuncios',
                    ),
                    onTap: _openPaywall,
                  ),
                ),
                const Divider(),

                // ── Cuenta ─────────────────────────────────────────────────
                ListTile(
                  leading: const Icon(Icons.lock_reset),
                  title: const Text('Cambiar contraseña'),
                  subtitle: const Text('Te enviaremos un enlace por correo'),
                  onTap: _sendPasswordReset,
                ),
                ListTile(
                  leading: const Icon(Icons.logout),
                  title: const Text('Cerrar sesión'),
                  onTap: _signOut,
                ),
                const Divider(),

                // ── Privacidad ─────────────────────────────────────────────
                ValueListenableBuilder<bool>(
                  valueListenable:
                      ConsentService.instance.privacyOptionsRequired,
                  builder: (context, required, _) => required
                      ? ListTile(
                          leading: const Icon(Icons.privacy_tip_outlined),
                          title: const Text('Opciones de privacidad'),
                          subtitle: const Text(
                            'Cambia tu consentimiento de anuncios',
                          ),
                          onTap: () => ConsentService.instance
                              .showPrivacyOptionsForm(),
                        )
                      : const SizedBox.shrink(),
                ),
                ListTile(
                  leading: const Icon(Icons.description_outlined),
                  title: const Text('Política de privacidad'),
                  onTap: () => LegalLinks.open(LegalLinks.privacyPolicy),
                ),
                const Divider(),

                // ── Zona peligrosa ─────────────────────────────────────────
                ListTile(
                  leading: const Icon(Icons.delete_forever, color: Colors.red),
                  title: const Text(
                    'Eliminar cuenta',
                    style: TextStyle(color: Colors.red),
                  ),
                  subtitle: const Text('Borra tu cuenta y todos tus datos'),
                  onTap: _deleteAccount,
                ),
              ],
            ),
            if (_busy)
              const Positioned.fill(
                child: ColoredBox(
                  color: Color(0x33000000),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
