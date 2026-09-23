// lib/core/firebaseCrudService.dart
//
// SEGURIDAD: los errores de login son genéricos a propósito. Decir "no existe
// una cuenta con ese correo" permite averiguar qué emails están registrados.

import 'package:firebase_auth/firebase_auth.dart';

class FirebaseCrudService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Constructor por defecto, sin parámetros
  FirebaseCrudService();

  /// Longitud mínima exigida en el registro (Firebase por defecto solo pide 6).
  static const int minPasswordLength = 8;

  /// Inicia sesión con email y contraseña.
  /// Lanza Exception con mensaje legible si hay error.
  Future<UserCredential> signInWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      return await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      throw Exception(_signInError(e));
    }
  }

  /// Registra un usuario con email y contraseña.
  /// Lanza Exception con mensaje legible si hay error.
  Future<UserCredential> registerWithEmail({
    required String email,
    required String password,
  }) async {
    final pwError = validatePassword(password);
    if (pwError != null) throw Exception(pwError);
    try {
      return await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      throw Exception(_registerError(e));
    }
  }

  /// Devuelve null si la contraseña es válida, o el motivo si no lo es.
  static String? validatePassword(String password) {
    if (password.length < minPasswordLength) {
      return 'La contraseña debe tener al menos $minPasswordLength caracteres.';
    }
    final hasLetter = RegExp(r'[A-Za-z]').hasMatch(password);
    final hasDigit = RegExp(r'\d').hasMatch(password);
    if (!hasLetter || !hasDigit) {
      return 'La contraseña debe combinar letras y números.';
    }
    return null;
  }

  String _signInError(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return 'El correo electrónico no tiene un formato válido.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
      case 'INVALID_LOGIN_CREDENTIALS':
        return 'Correo o contraseña incorrectos.';
      case 'user-disabled':
        return 'Esta cuenta está desactivada.';
      case 'too-many-requests':
        return 'Demasiados intentos. Espera unos minutos e inténtalo de nuevo.';
      case 'network-request-failed':
        return 'Sin conexión. Revisa tu red e inténtalo de nuevo.';
      default:
        return 'No se pudo iniciar sesión. Inténtalo de nuevo.';
    }
  }

  String _registerError(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return 'El correo electrónico no tiene un formato válido.';
      case 'email-already-in-use':
        return 'No se pudo crear la cuenta con ese correo. Si ya tienes una, inicia sesión.';
      case 'weak-password':
      case 'password-does-not-meet-requirements':
        return 'La contraseña no cumple los requisitos de seguridad.';
      case 'too-many-requests':
        return 'Demasiados intentos. Espera unos minutos e inténtalo de nuevo.';
      case 'network-request-failed':
        return 'Sin conexión. Revisa tu red e inténtalo de nuevo.';
      default:
        return 'No se pudo crear la cuenta. Inténtalo de nuevo.';
    }
  }
}
