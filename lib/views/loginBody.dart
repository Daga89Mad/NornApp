// lib/views/loginBody.dart
//
// SEGURIDAD: "Recuérdame" ya NO guarda la contraseña. Firebase Auth mantiene
// la sesión iniciada por sí mismo (token de refresco), así que guardar la
// contraseña en el dispositivo no aporta nada y es un riesgo. Ahora solo se
// recuerda el email.

import 'package:nornapp/core/firebaseCrudService.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:nornapp/views/menu.dart';
import 'package:nornapp/views/registerScreen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:nornapp/core/db_provider.dart';
import 'package:nornapp/core/firebase_sync_service.dart';
import 'package:nornapp/core/push_notification_service.dart';
import 'package:nornapp/core/monetization/premium_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class LoginBody extends StatefulWidget {
  const LoginBody({super.key});

  @override
  State<LoginBody> createState() => _LoginBodyState();
}

class _LoginBodyState extends State<LoginBody> {
  final FirebaseCrudService _authService = FirebaseCrudService();
  final TextEditingController _emailCtrl = TextEditingController();
  final TextEditingController _passCtrl = TextEditingController();

  static const _kRememberEmail = 'remember_me';
  static const _kSavedEmail = 'saved_email';

  bool _obscurePassword = true;
  bool _isLoading = false;
  bool _remember = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadSavedEmail();
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  // ── Email guardado ────────────────────────────────────────────────────────

  Future<void> _loadSavedEmail() async {
    // Borra la contraseña que guardaban versiones anteriores de la app.
    try {
      await const FlutterSecureStorage().delete(key: 'saved_pass');
    } catch (_) {}

    final prefs = await SharedPreferences.getInstance();
    final remember = prefs.getBool(_kRememberEmail) ?? false;
    if (!remember) return;

    final savedEmail = prefs.getString(_kSavedEmail);
    if (savedEmail != null) _emailCtrl.text = savedEmail;

    if (mounted) setState(() => _remember = true);
  }

  Future<void> _persistRememberChoice() async {
    final prefs = await SharedPreferences.getInstance();
    if (_remember) {
      await prefs.setBool(_kRememberEmail, true);
      await prefs.setString(_kSavedEmail, _emailCtrl.text.trim());
    } else {
      await prefs.remove(_kRememberEmail);
      await prefs.remove(_kSavedEmail);
    }
  }

  // ── Login ─────────────────────────────────────────────────────────────────

  Future<void> _signIn() async {
    final email = _emailCtrl.text.trim();
    final password = _passCtrl.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _errorMessage = 'Introduce tu correo y tu contraseña.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await _authService.signInWithEmail(email: email, password: password);

      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        // 1. Inicializar BD local (la de ESTE usuario)
        await DBProvider.db.database;

        // 2. Guardar / actualizar perfil en Firestore (para búsqueda de amigos)
        await FirebaseFirestore.instance
            .collection('user_profiles')
            .doc(user.uid)
            .set({
              'uid': user.uid,
              'email': (user.email ?? '').toLowerCase(),
              'name': user.displayName ?? user.email?.split('@').first ?? '',
              'created_at': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));

        // 3. Token FCM para notificaciones push
        await PushNotificationService.instance.onUserLoggedIn();

        // 4. Sync inicial: Firebase → SQLite
        await FirebaseSyncService.instance.pullAll(user.uid);

        // 5. Listener en tiempo real de eventos compartidos
        FirebaseSyncService.instance.startListening(user.uid);

        // 6. ¿Tiene Premium concedido manualmente?
        await PremiumService.instance.refreshGrant();
      }

      await _persistRememberChoice();
      _passCtrl.clear(); // no dejar la contraseña en memoria del widget

      if (!mounted) return;
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const MenuScreen()));
    } on Exception catch (e) {
      if (mounted) {
        setState(
          () => _errorMessage = e.toString().replaceFirst('Exception: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _forgotPassword() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      setState(() => _errorMessage = 'Escribe tu correo para recuperar la contraseña.');
      return;
    }
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
    } catch (_) {
      // No se revela si el correo existe o no.
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Si el correo está registrado, recibirás un enlace para cambiar la contraseña.',
        ),
      ),
    );
  }

  void _goToRegister() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const RegisterScreen()));
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: SingleChildScrollView(
            child: AutofillGroup(
              child: Column(
                children: [
                  Image.asset(
                    'assets/images/LogoGrande.png',
                    height: 220,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(height: 1),

                  // Email
                  TextField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(
                      labelText: 'Correo electrónico',
                      prefixIcon: Icon(Icons.email),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Contraseña (el gestor de contraseñas del sistema puede
                  // rellenarla gracias a autofillHints)
                  TextField(
                    controller: _passCtrl,
                    obscureText: _obscurePassword,
                    autocorrect: false,
                    enableSuggestions: false,
                    autofillHints: const [AutofillHints.password],
                    onSubmitted: (_) => _signIn(),
                    decoration: InputDecoration(
                      labelText: 'Contraseña',
                      prefixIcon: const Icon(Icons.lock),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility
                              : Icons.visibility_off,
                        ),
                        onPressed: () => setState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Recordar email
                  CheckboxListTile(
                    title: const Text('Recordar mi correo'),
                    value: _remember,
                    onChanged: (v) => setState(() => _remember = v ?? false),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),

                  // Error
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _errorMessage!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ],

                  const SizedBox(height: 16),

                  // Botón login
                  _isLoading
                      ? const CircularProgressIndicator()
                      : ElevatedButton(
                          onPressed: _signIn,
                          child: const Text('Iniciar sesión'),
                        ),
                  const SizedBox(height: 4),

                  TextButton(
                    onPressed: _isLoading ? null : _forgotPassword,
                    child: const Text('¿Has olvidado la contraseña?'),
                  ),

                  // Registro
                  TextButton(
                    onPressed: _goToRegister,
                    child: const Text('¿Nuevo usuario? Regístrate'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
