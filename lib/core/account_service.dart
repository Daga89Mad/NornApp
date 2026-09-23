// lib/core/account_service.dart
//
// Cierre de sesión seguro y eliminación de cuenta.
//
// · signOut(): corta listeners, da de baja el token FCM, cierra la BD local
//   del usuario y cierra sesión en Firebase. NO borra datos locales: cada
//   usuario tiene su propia BD (ver DBProvider) y su propio diario.
//
// · deleteAccount(): requisito obligatorio de App Store (guía 5.1.1(v)) y de
//   Google Play. Borra los datos del usuario en Firestore, los datos locales
//   del dispositivo y finalmente la cuenta de Firebase Auth.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'alarm_service.dart';
import 'date_change_service.dart';
import 'db_provider.dart';
import 'firebase_sync_service.dart';
import 'push_notification_service.dart';
import 'weekly_share_service.dart';
import 'weekly_training_repository.dart';

/// Resultado de [AccountService.deleteAccount].
enum DeleteAccountResult { ok, wrongPassword, requiresRecentLogin, error }

class AccountService {
  AccountService._();
  static final AccountService instance = AccountService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  static const FlutterSecureStorage _secure = FlutterSecureStorage();

  // Colecciones cuyos documentos tienen 'owner_id'
  static const List<String> _ownedCollections = [
    'events',
    'shifts',
    'shift_assignments',
    'friends',
    'calendar_categories',
    'weekly_menus',
    'weekly_tasks',
    'weekly_trainings',
  ];

  // ══════════════════════════════════════════════════════════════════════════
  // LOGOUT
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> signOut() async {
    _stopAllListeners();

    // Sin esto el móvil seguiría recibiendo los push del usuario anterior.
    try {
      await PushNotificationService.instance.onUserLoggedOut();
    } catch (e) {
      debugPrint('⚠️ FCM logout: $e');
    }

    // Las alarmas locales son del usuario que se va.
    try {
      await AlarmService.plugin.cancelAll();
    } catch (_) {}

    await DBProvider.db.reset();

    // Limpia restos del antiguo "Recuérdame" (guardaba la contraseña).
    await _clearLegacyCredentials();

    await _auth.signOut();
  }

  // ══════════════════════════════════════════════════════════════════════════
  // ELIMINAR CUENTA
  // ══════════════════════════════════════════════════════════════════════════

  /// Borra la cuenta y todos sus datos. Pide la contraseña para
  /// reautenticar (Firebase exige un login reciente para borrar la cuenta).
  Future<DeleteAccountResult> deleteAccount({required String password}) async {
    final user = _auth.currentUser;
    if (user == null || user.email == null) return DeleteAccountResult.error;
    final uid = user.uid;

    // 1. Reautenticar ANTES de borrar nada
    try {
      final cred = EmailAuthProvider.credential(
        email: user.email!,
        password: password,
      );
      await user.reauthenticateWithCredential(cred);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
        return DeleteAccountResult.wrongPassword;
      }
      debugPrint('❌ Reauth: ${e.code}');
      return DeleteAccountResult.error;
    }

    _stopAllListeners();

    // 2. Datos en Firestore
    try {
      await _deleteFirestoreData(uid);
    } catch (e) {
      debugPrint('❌ Borrado Firestore: $e');
      return DeleteAccountResult.error;
    }

    // 3. Token FCM (el perfil ya no existe, solo se invalida el token)
    try {
      await FirebaseMessaging.instance.deleteToken();
    } catch (_) {}

    // 4. Datos locales del dispositivo
    try {
      await AlarmService.plugin.cancelAll();
    } catch (_) {}
    await DBProvider.db.deleteDatabaseForUid(uid);
    await _deleteLocalDiary(uid);
    await _clearLegacyCredentials();

    // 5. Cuenta de Firebase Auth (al final: si falla antes, el usuario
    //    aún puede entrar y reintentar)
    try {
      await user.delete();
    } on FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login') {
        return DeleteAccountResult.requiresRecentLogin;
      }
      debugPrint('❌ user.delete: ${e.code}');
      return DeleteAccountResult.error;
    }

    await _auth.signOut();
    return DeleteAccountResult.ok;
  }

  // ── Firestore ──────────────────────────────────────────────────────────────

  Future<void> _deleteFirestoreData(String uid) async {
    // Documentos propios
    for (final col in _ownedCollections) {
      await _deleteQuery(_db.collection(col).where('owner_id', isEqualTo: uid));
    }

    // Documentos donde participo como emisor o receptor
    for (final col in const [
      'friend_requests',
      'calendar_shares',
      'weekly_shares',
      'date_change_requests',
    ]) {
      await _deleteQuery(_db.collection(col).where('from_uid', isEqualTo: uid));
      await _deleteQuery(_db.collection(col).where('to_uid', isEqualTo: uid));
    }

    // Copia del diario
    await _deleteQuery(_db.collection('users').doc(uid).collection('diary'));

    // Perfil público (email, nombre, tokens FCM)
    await _db.collection('user_profiles').doc(uid).delete();
  }

  /// Borra en lotes de 400 (límite de Firestore: 500 operaciones por batch).
  Future<void> _deleteQuery(Query<Map<String, dynamic>> query) async {
    while (true) {
      QuerySnapshot<Map<String, dynamic>> snap;
      try {
        snap = await query.limit(400).get();
      } on FirebaseException catch (e) {
        // Si una regla no permite leer una colección, no bloqueamos el resto.
        debugPrint('⚠️ No se pudo consultar para borrar: ${e.code}');
        return;
      }
      if (snap.docs.isEmpty) return;
      final batch = _db.batch();
      for (final d in snap.docs) {
        batch.delete(d.reference);
      }
      try {
        await batch.commit();
      } on FirebaseException catch (e) {
        debugPrint('⚠️ No se pudo borrar un lote: ${e.code}');
        return;
      }
      if (snap.docs.length < 400) return;
    }
  }

  // ── Local ──────────────────────────────────────────────────────────────────

  Future<void> _deleteLocalDiary(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    final prefix = 'diary_${uid}_';
    for (final k in prefs.getKeys().where((k) => k.startsWith(prefix))) {
      await prefs.remove(k);
    }
    await _secure.delete(key: 'diary_pin_$uid');
  }

  Future<void> _clearLegacyCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('saved_email');
    await prefs.remove('remember_me');
    await _secure.delete(key: 'saved_pass');
  }

  void _stopAllListeners() {
    FirebaseSyncService.instance.stopListening();
    WeeklyShareService.instance.stopListening();
    WeeklyTrainingRepository.instance.stopListening();
    DateChangeService.instance.stopListening();
  }
}
