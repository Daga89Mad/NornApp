// lib/views/loginBody.dart

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
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  bool _obscurePassword = true;
  bool _isLoading = false;
  bool _remember = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadSavedCredentials();
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  // ── Credenciales guardadas ────────────────────────────────────────────────

  Future<void> _loadSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final remember = prefs.getBool('remember_me') ?? false;
    if (!remember) return;

    final savedEmail = prefs.getString('saved_email');
    final savedPass = await _secureStorage.read(key: 'saved_pass');

    if (savedEmail != null) _emailCtrl.text = savedEmail;
    if (savedPass != null) _passCtrl.text = savedPass;

    setState(() => _remember = true);
  }

  // ── Login ─────────────────────────────────────────────────────────────────

  Future<void> _signIn() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await _authService.signInWithEmail(
        email: _emailCtrl.text.trim(),
        password: _passCtrl.text,
      );

      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        // 1. Inicializar BD local
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
      }

      // Gestión de "Recuérdame"
      final prefs = await SharedPreferences.getInstance();
      if (_remember) {
        await prefs.setBool('remember_me', true);
        await prefs.setString('saved_email', _emailCtrl.text.trim());
        await _secureStorage.write(key: 'saved_pass', value: _passCtrl.text);
      } else {
        await prefs.remove('remember_me');
        await prefs.remove('saved_email');
        await _secureStorage.delete(key: 'saved_pass');
      }

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
                  decoration: const InputDecoration(
                    labelText: 'Correo electrónico',
                    prefixIcon: Icon(Icons.email),
                  ),
                ),
                const SizedBox(height: 16),

                // Contraseña
                TextField(
                  controller: _passCtrl,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    labelText: 'Contraseña',
                    prefixIcon: const Icon(Icons.lock),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility
                            : Icons.visibility_off,
                      ),
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Recuérdame
                CheckboxListTile(
                  title: const Text('Recuérdame'),
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
                const SizedBox(height: 12),

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
    );
  }
}
