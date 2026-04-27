// lib/views/register_screen.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:nornapp/core/firebaseCrudService.dart';
import 'package:nornapp/core/db_provider.dart';
import 'package:nornapp/core/firebase_sync_service.dart';
import 'package:nornapp/core/push_notification_service.dart';
import 'package:nornapp/views/menu.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({Key? key}) : super(key: key);

  @override
  _RegisterScreenState createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final _nameCtrl = TextEditingController(); // ← nombre opcional
  final _authService = FirebaseCrudService();

  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;
    final confirm = _confirmCtrl.text;
    final name = _nameCtrl.text.trim();

    if (email.isEmpty || password.isEmpty || confirm.isEmpty) {
      setState(() => _errorMessage = 'Rellena todos los campos');
      return;
    }
    if (password != confirm) {
      setState(() => _errorMessage = 'Las contraseñas no coinciden');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // 1. Crear cuenta en Firebase Auth
      await _authService.registerWithEmail(email: email, password: password);

      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        // 2. Actualizar displayName si el usuario introdujo nombre
        final displayName = name.isNotEmpty ? name : email.split('@').first;
        await user.updateDisplayName(displayName);

        // 3. ← CORRECCIÓN PRINCIPAL: guardar perfil en Firestore
        //    Sin este paso el usuario no aparece en búsquedas de amigos.
        await FirebaseFirestore.instance
            .collection('user_profiles')
            .doc(user.uid)
            .set({
              'uid': user.uid,
              'email': email.toLowerCase(),
              'name': displayName,
              'created_at': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));

        // 4. Inicializar BD local
        await DBProvider.db.database;

        // 5. Token FCM para notificaciones push
        await PushNotificationService.instance.onUserLoggedIn();

        // 6. Sync inicial (vacío en registro nuevo, pero deja el listener activo)
        await FirebaseSyncService.instance.pullAll(user.uid);
        FirebaseSyncService.instance.startListening(user.uid);
      }

      if (!mounted) return;
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const MenuScreen()));
    } on Exception catch (e) {
      setState(
        () => _errorMessage = e.toString().replaceFirst('Exception: ', ''),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Registro de Usuario')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: SingleChildScrollView(
            child: Column(
              children: [
                // Nombre (opcional)
                TextField(
                  controller: _nameCtrl,
                  keyboardType: TextInputType.name,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Nombre (opcional)',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                ),

                const SizedBox(height: 16),

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
                  controller: _passwordCtrl,
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

                const SizedBox(height: 16),

                // Confirmar contraseña
                TextField(
                  controller: _confirmCtrl,
                  obscureText: _obscurePassword,
                  decoration: const InputDecoration(
                    labelText: 'Confirmar contraseña',
                    prefixIcon: Icon(Icons.lock_outline),
                  ),
                ),

                const SizedBox(height: 12),

                // Error
                if (_errorMessage != null) ...[
                  Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.red),
                  ),
                  const SizedBox(height: 12),
                ],

                // Botón Registrar
                _isLoading
                    ? const CircularProgressIndicator()
                    : ElevatedButton(
                        onPressed: _register,
                        child: const Text('Registrar'),
                      ),

                const SizedBox(height: 16),

                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('¿Ya tienes cuenta? Iniciar sesión'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
