// lib/core/calendar_share_service.dart
//
// Gestiona el compartir categorías de calendario con amigos.
// Al compartir:
//   1. Escribe un documento en 'calendar_shares' (qué categorías comparte A con B)
//   2. Actualiza los eventos existentes de esas categorías añadiendo B en shared_with
//   3. Los nuevos eventos se comparten automáticamente en EventRepository.save()

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../models/friend_model.dart';

class CalendarShareService {
  CalendarShareService._();
  static final CalendarShareService instance = CalendarShareService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ── Compartir ─────────────────────────────────────────────────────────────

  /// Comparte las categorías indicadas con los amigos indicados.
  /// Actualiza eventos existentes y guarda la configuración de compartir.
  Future<void> shareWithFriends({
    required List<String> categories,
    required List<FriendModel> friends,
  }) async {
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    if (myUid == null) return;

    final friendUids = friends
        .where((f) => f.firebaseUid != null)
        .map((f) => f.firebaseUid!)
        .toList();

    if (friendUids.isEmpty) return;

    // 1. Guardar / actualizar configuración de compartir en Firestore
    for (final friendUid in friendUids) {
      await _db.collection('calendar_shares').doc('${myUid}_$friendUid').set({
        'from_uid': myUid,
        'to_uid': friendUid,
        'categories': categories,
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    // 2. Actualizar eventos existentes con shared_with
    final eventsSnap = await _db
        .collection('events')
        .where('owner_id', isEqualTo: myUid)
        .get();

    final batch = _db.batch();
    int updatedEvents = 0;

    for (final doc in eventsSnap.docs) {
      final data = doc.data();
      final category = (data['category'] as String? ?? '').toLowerCase();
      final matches = categories.any(
        (c) => c.toLowerCase() == category || _categoryMatches(c, category),
      );
      if (!matches) continue;

      final currentShared = List<String>.from(
        data['shared_with'] as List<dynamic>? ?? [],
      );
      final toAdd = friendUids
          .where((u) => !currentShared.contains(u))
          .toList();
      if (toAdd.isEmpty) continue;

      batch.update(doc.reference, {
        'shared_with': FieldValue.arrayUnion(toAdd),
        'updated_at': FieldValue.serverTimestamp(),
      });
      updatedEvents++;
    }

    await batch.commit();

    // 3. Actualizar shift_assignments existentes si "turnos" está seleccionado
    if (categories.any((c) => c.toLowerCase() == 'turnos')) {
      await _shareExistingShiftAssignments(myUid, friendUids);
    }

    debugPrint('📤 Compartido: $updatedEvents eventos + turnos procesados');
  }

  /// Actualiza los shift_assignments existentes en Firestore añadiendo
  /// los UIDs de los amigos al campo shared_with.
  Future<void> _shareExistingShiftAssignments(
    String myUid,
    List<String> friendUids,
  ) async {
    try {
      final snap = await _db
          .collection('shift_assignments')
          .where('owner_id', isEqualTo: myUid)
          .get();

      if (snap.docs.isEmpty) return;

      final batch = _db.batch();
      int updated = 0;

      for (final doc in snap.docs) {
        final data = doc.data();
        final currentShared = List<String>.from(
          data['shared_with'] as List<dynamic>? ?? [],
        );
        final toAdd = friendUids
            .where((u) => !currentShared.contains(u))
            .toList();
        if (toAdd.isEmpty) continue;

        batch.update(doc.reference, {
          'shared_with': FieldValue.arrayUnion(toAdd),
          'updated_at': FieldValue.serverTimestamp(),
        });
        updated++;
      }

      await batch.commit();
      debugPrint('📤 $updated shift_assignments actualizados con shared_with');
    } catch (e) {
      debugPrint('❌ Error compartiendo turnos: \$e');
    }
  }

  /// Obtiene la configuración de compartir activa de otro usuario hacia mí.
  Future<List<String>> getSharedCategoriesFrom(String fromUid) async {
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    if (myUid == null) return [];
    try {
      final doc = await _db
          .collection('calendar_shares')
          .doc('${fromUid}_$myUid')
          .get();
      if (!doc.exists) return [];
      return List<String>.from(doc.data()?['categories'] ?? []);
    } catch (_) {
      return [];
    }
  }

  // ── Helper ─────────────────────────────────────────────────────────────────

  bool _categoryMatches(String selected, String eventCategory) {
    const map = {
      'trabajo': 'laboral',
      'eventos': 'evento',
      'citas': 'cita',
      'recordatorios': 'recordatorio',
      'bebe': 'bebe',
      'periodo': 'periodo',
      'turnos': 'turno',
    };
    return map[selected.toLowerCase()] == eventCategory.toLowerCase() ||
        selected.toLowerCase() == eventCategory.toLowerCase();
  }
}
