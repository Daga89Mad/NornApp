// lib/core/profile_service.dart
//
// Nombre y foto del usuario actual.
//
// · Nombre → FirebaseAuth.displayName + user_profiles/{uid}.name
//            (este último es el que ven los amigos y las solicitudes).
// · Foto   → JPEG pequeño (≈256 px) en base64 dentro de user_profiles/{uid}.photo
//            y copia local en SharedPreferences para mostrarla al instante.
//
// La UI escucha [name] y [photo] (ValueNotifier) para refrescarse sola.

import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ProfileService {
  ProfileService._();
  static final ProfileService instance = ProfileService._();

  final ValueNotifier<String> name = ValueNotifier<String>('');
  final ValueNotifier<Uint8List?> photo = ValueNotifier<Uint8List?>(null);

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  String? _loadedFor;

  User? get _user => FirebaseAuth.instance.currentUser;
  String _prefsKey(String uid) => 'profile_photo_$uid';

  /// Carga nombre y foto (primero caché local, luego Firestore).
  Future<void> load({bool force = false}) async {
    final user = _user;
    if (user == null) {
      name.value = '';
      photo.value = null;
      _loadedFor = null;
      return;
    }
    if (!force && _loadedFor == user.uid) return;
    _loadedFor = user.uid;

    name.value = user.displayName ?? user.email?.split('@').first ?? 'Usuario';

    // 1) Caché local (instantáneo)
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(_prefsKey(user.uid));
      photo.value = (cached == null || cached.isEmpty)
          ? null
          : base64Decode(cached);
    } catch (_) {
      photo.value = null;
    }

    // 2) Firestore (por si se cambió desde otro dispositivo)
    try {
      final snap = await _db.collection('user_profiles').doc(user.uid).get();
      final data = snap.data();
      if (data == null) return;
      final n = data['name'] as String?;
      if (n != null && n.isNotEmpty) name.value = n;
      final b64 = data['photo'] as String? ?? '';
      final prefs = await SharedPreferences.getInstance();
      if (b64.isEmpty) {
        photo.value = null;
        await prefs.remove(_prefsKey(user.uid));
      } else {
        photo.value = base64Decode(b64);
        await prefs.setString(_prefsKey(user.uid), b64);
      }
    } catch (e) {
      debugPrint('⚠️ No se pudo leer el perfil de Firestore: $e');
    }
  }

  /// Guarda nombre y foto. [newPhoto] null + [removePhoto] true = quitar foto.
  Future<void> save({
    required String newName,
    Uint8List? newPhoto,
    bool removePhoto = false,
  }) async {
    final user = _user;
    if (user == null) return;
    final trimmed = newName.trim();

    // Nombre
    if (trimmed.isNotEmpty && trimmed != user.displayName) {
      await user.updateDisplayName(trimmed);
      await user.reload();
    }

    final payload = <String, dynamic>{
      'uid': user.uid,
      'email': (user.email ?? '').toLowerCase(),
      if (trimmed.isNotEmpty) 'name': trimmed,
      'updated_at': FieldValue.serverTimestamp(),
    };

    final prefs = await SharedPreferences.getInstance();
    if (removePhoto) {
      payload['photo'] = '';
      await prefs.remove(_prefsKey(user.uid));
      photo.value = null;
    } else if (newPhoto != null) {
      final b64 = base64Encode(newPhoto);
      payload['photo'] = b64;
      await prefs.setString(_prefsKey(user.uid), b64);
      photo.value = newPhoto;
    }

    await _db
        .collection('user_profiles')
        .doc(user.uid)
        .set(payload, SetOptions(merge: true));

    if (trimmed.isNotEmpty) name.value = trimmed;
  }

  /// Llamar al cerrar sesión para no enseñar la foto del usuario anterior.
  void clear() {
    _loadedFor = null;
    name.value = '';
    photo.value = null;
  }
}
