// lib/core/firebase_sync_service.dart
//
// Sincronización bidireccional SQLite ↔ Firestore.
//
// Estrategia:
//  - Login      → pullAll()  : Firebase → SQLite (todo del usuario + compartido)
//  - Escritura  → pushXxx()  : SQLite + Firestore simultáneamente
//  - Tiempo real→ startListening() : snapshot de eventos compartidos → SQLite
//
// Las tablas de contenido estático (jokes, phrases, language_words,
// interesting_facts) NO se sincronizan.

import 'dart:async';
import 'package:flutter/foundation.dart' show VoidCallback, debugPrint;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart' show Color;
import '../models/event_item.dart';
import '../models/shift_model.dart';
import '../models/friend_model.dart';
import '../models/shift_model.dart';
import '../models/friend_request_model.dart';
import 'db_provider.dart';
import 'db_schema.dart';

class FirebaseSyncService {
  FirebaseSyncService._();
  static final FirebaseSyncService instance = FirebaseSyncService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Listeners activos (cancelar al logout)
  final List<StreamSubscription> _subscriptions = [];

  // ── Helpers de conversión ─────────────────────────────────────────────────

  int _dayMs(DateTime d) =>
      DateTime.utc(d.year, d.month, d.day).millisecondsSinceEpoch;

  Timestamp? _tsFromMs(int? ms) =>
      ms != null ? Timestamp.fromMillisecondsSinceEpoch(ms) : null;

  int? _msFromTs(dynamic ts) =>
      ts is Timestamp ? ts.millisecondsSinceEpoch : null;

  // ══════════════════════════════════════════════════════════════════════════
  // PULL — Firebase → SQLite  (se llama al hacer login)
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> pullAll(String uid) async {
    debugPrint('🔄 Iniciando sync pull para uid=$uid');
    await Future.wait([
      _pullEvents(uid),
      _pullShifts(uid),
      _pullShiftAssignments(uid),
      _pullFriends(uid),
      pullAcceptedRequests(
        uid,
      ), // amistades aceptadas que aún no tenemos localmente
    ]);
    debugPrint('✅ Sync pull completado');
  }

  // ── Pull: Eventos ─────────────────────────────────────────────────────────

  Future<void> _pullEvents(String uid) async {
    try {
      // Propios
      final own = await _db
          .collection('events')
          .where('owner_id', isEqualTo: uid)
          .get();

      // Compartidos con el usuario
      final shared = await _db
          .collection('events')
          .where('shared_with', arrayContains: uid)
          .get();

      final allDocs = {...own.docs, ...shared.docs};
      if (allDocs.isEmpty) return;

      final rows = allDocs.map((d) {
        final data = d.data();
        return {
          'id': d.id,
          'title': data['title'] ?? '',
          'description': data['description'] ?? '',
          'date': _msFromTs(data['date']) ?? 0,
          'from_minutes': data['from_minutes'] ?? 0,
          'to_minutes': data['to_minutes'] ?? 60,
          'category': data['category'] ?? 'Evento',
          'tipo': data['tipo'] ?? 'Otros',
          'icon': data['icon'] ?? '',
          'creator': data['creator'] ?? '',
          'users': data['users'] ?? '',
          'color': data['color'] ?? 4280391411,
          'owner_id': data['owner_id'] ?? uid,
          'synced': 1,
          'has_alarm': (data['has_alarm'] ?? false) ? 1 : 0,
          'alarm_at': _msFromTs(data['alarm_at']),
          'has_notification': (data['has_notification'] ?? false) ? 1 : 0,
          'notification_at': _msFromTs(data['notification_at']),
          'solo_para_mi': (data['solo_para_mi'] ?? false) ? 1 : 0,
        };
      }).toList();

      await DBProvider.db.batchInsert(DBSchema.tableEvents, rows);
      debugPrint('📥 ${rows.length} eventos sincronizados');
    } catch (e) {
      debugPrint('❌ Error pull events: $e');
    }
  }

  // ── Pull: Turnos ──────────────────────────────────────────────────────────

  Future<void> _pullShifts(String uid) async {
    try {
      final snap = await _db
          .collection('shifts')
          .where('owner_id', isEqualTo: uid)
          .get();
      if (snap.docs.isEmpty) return;

      final rows = snap.docs.map((d) {
        final data = d.data();
        return {
          'id': d.id,
          'name': data['name'] ?? '',
          'color': data['color'] ?? 4280391411,
          'from_minutes': data['from_minutes'] ?? 0,
          'to_minutes': data['to_minutes'] ?? 0,
          'euro_per_hour': data['euro_per_hour'],
          'sort_order': data['sort_order'] ?? 0,
        };
      }).toList();

      await DBProvider.db.batchInsert(DBSchema.tableShifts, rows);
      debugPrint('📥 ${rows.length} turnos sincronizados');
    } catch (e) {
      debugPrint('❌ Error pull shifts: $e');
    }
  }

  // ── Pull: Asignaciones de turno ───────────────────────────────────────────

  Future<void> _pullShiftAssignments(String uid) async {
    try {
      final snap = await _db
          .collection('shift_assignments')
          .where('owner_id', isEqualTo: uid)
          .get();
      if (snap.docs.isEmpty) return;

      final rows = snap.docs.map((d) {
        final data = d.data();
        return {
          'id': d.id,
          'shift_id': data['shift_id'] ?? '',
          'date': _msFromTs(data['date']) ?? 0,
        };
      }).toList();

      await DBProvider.db.batchInsert(DBSchema.tableShiftAssignments, rows);
      debugPrint('📥 ${rows.length} asignaciones sincronizadas');
    } catch (e) {
      debugPrint('❌ Error pull shift_assignments: $e');
    }
  }

  // ── Pull: Solicitudes aceptadas (relación inversa) ───────────────────────────
  // Cuando A envió una solicitud y B la aceptó, A necesita saber que B
  // es ahora su amigo. Lo detectamos buscando solicitudes enviadas por A
  // con status 'accepted' y guardamos a B como amigo local si no existe ya.

  Future<void> pullAcceptedRequests(String uid) async {
    try {
      // Solo buscamos 'accepted' — 'synced' y 'removed' ya fueron procesadas
      final snap = await _db
          .collection('friend_requests')
          .where('from_uid', isEqualTo: uid)
          .where('status', isEqualTo: 'accepted')
          .get();

      if (snap.docs.isEmpty) return;

      for (final doc in snap.docs) {
        final data = doc.data();
        final toUid = data['to_uid'] as String? ?? '';
        final toEmail = data['to_email'] as String? ?? '';
        if (toUid.isEmpty) continue;

        // Obtener perfil actualizado del amigo
        final profileSnap = await _db
            .collection('user_profiles')
            .doc(toUid)
            .get();
        final profileData = profileSnap.data();
        final toName = (profileData?['name'] as String?) ?? toEmail;

        // Solo añadir si no existe ya localmente
        final existing = await DBProvider.db.query(
          DBSchema.tableFriends,
          where: 'firebase_uid = ?',
          whereArgs: [toUid],
        );

        if (existing.isEmpty) {
          // Usar el logo que el emisor eligió (guardado en from_logo
          // de la solicitud), no el logo por defecto
          final chosenLogo = (data['from_logo'] as String?)?.isNotEmpty == true
              ? data['from_logo'] as String
              : '😊';
          await DBProvider.db.insertOrReplace(DBSchema.tableFriends, {
            'id': '${DateTime.now().millisecondsSinceEpoch}_$toUid',
            'name': toName,
            'email': toEmail,
            'alias': '',
            'logo': chosenLogo,
            'firebase_uid': toUid,
          });
          debugPrint('👥 Amigo añadido: $toName con logo $chosenLogo');
        }

        // Marcar como 'synced' para que no se vuelva a procesar nunca más.
        // Si la amistad se elimina después, delete() lo marcará como 'removed'.
        await doc.reference.update({'status': 'synced'});
      }
    } catch (e) {
      debugPrint('❌ Error pull accepted requests: $e');
    }
  }

  // ── Pull: Amigos ──────────────────────────────────────────────────────────

  Future<void> _pullFriends(String uid) async {
    try {
      final snap = await _db
          .collection('friends')
          .where('owner_id', isEqualTo: uid)
          .get();
      if (snap.docs.isEmpty) return;

      final rows = snap.docs.map((d) {
        final data = d.data();
        return {
          'id': d.id,
          'name': data['name'] ?? '',
          'email': data['email'] ?? '',
          'alias': data['alias'] ?? '',
          'logo': data['logo'] ?? '😊',
          'firebase_uid': data['friend_uid'],
        };
      }).toList();

      await DBProvider.db.batchInsert(DBSchema.tableFriends, rows);
      debugPrint('📥 ${rows.length} amigos sincronizados');
    } catch (e) {
      debugPrint('❌ Error pull friends: $e');
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // PUSH — SQLite → Firebase  (se llama en cada escritura)
  // ══════════════════════════════════════════════════════════════════════════

  // ── Push: Evento ──────────────────────────────────────────────────────────

  Future<void> pushEvent(EventItem event, DateTime date) async {
    if (event.id == null) return;
    if (event.soloParaMi) return; // nunca sube a Firebase

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      // Obtener los UIDs con los que compartir esta categoría
      // leyendo la configuración en calendar_shares/{uid}_*
      final sharedWithUids = await _getSharedWithUids(uid, event.category.name);

      final dayUtc = DateTime.utc(date.year, date.month, date.day);
      await _db.collection('events').doc(event.id).set({
        'title': event.title,
        'description': event.description,
        'date': Timestamp.fromDate(dayUtc),
        'from_minutes': event.from.hour * 60 + event.from.minute,
        'to_minutes': event.to.hour * 60 + event.to.minute,
        'category': event.category.name,
        'tipo': event.tipo.name,
        'icon': event.icon,
        'color': event.color.value,
        'creator': event.creator,
        'users': event.users.join('|'),
        'owner_id': uid,
        'shared_with': sharedWithUids,
        'has_alarm': event.hasAlarm,
        'alarm_at': _tsFromMs(event.alarmAt?.millisecondsSinceEpoch),
        'has_notification': event.hasNotification,
        'notification_at': _tsFromMs(
          event.notificationAt?.millisecondsSinceEpoch,
        ),
        'solo_para_mi': false,
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      debugPrint(
        '📤 Evento subido: \${event.id} → shared_with: \$sharedWithUids',
      );
    } catch (e) {
      debugPrint('❌ Error push event: \$e');
    }
  }

  /// Lee todos los documentos calendar_shares donde from_uid == uid
  /// y devuelve los to_uid que tengan la categoría del evento en su lista.
  Future<List<String>> _getSharedWithUids(
    String uid,
    String categoryName,
  ) async {
    try {
      final snap = await _db
          .collection('calendar_shares')
          .where('from_uid', isEqualTo: uid)
          .get();

      if (snap.docs.isEmpty) return [];

      final List<String> result = [];
      for (final doc in snap.docs) {
        final data = doc.data();
        final toUid = data['to_uid'] as String? ?? '';
        final categories = List<String>.from(data['categories'] ?? []);
        if (toUid.isEmpty) continue;

        // Comparar categoría del evento con las configuradas (insensible a mayúsculas)
        final catLower = categoryName.toLowerCase();
        final matches = categories.any((c) {
          final cl = c.toLowerCase();
          // Mapeo entre nombres del enum Dart y las claves del diálogo
          if (catLower == 'laboral' && (cl == 'trabajo' || cl == 'laboral'))
            return true;
          if (catLower == 'evento' && (cl == 'eventos' || cl == 'evento'))
            return true;
          if (catLower == 'cita' && (cl == 'citas' || cl == 'cita'))
            return true;
          if (catLower == 'recordatorio' &&
              (cl == 'recordatorios' || cl == 'recordatorio'))
            return true;
          if (catLower == 'bebe' && cl == 'bebe') return true;
          if (catLower == 'periodo' && cl == 'periodo') return true;
          return cl == catLower;
        });

        if (matches) result.add(toUid);
      }
      return result;
    } catch (e) {
      debugPrint('⚠️ Error leyendo calendar_shares: \$e');
      return [];
    }
  }

  Future<void> deleteEvent(String eventId) async {
    try {
      await _db.collection('events').doc(eventId).delete();
      debugPrint('🗑️ Evento eliminado de Firebase: $eventId');
    } catch (e) {
      debugPrint('❌ Error delete event Firebase: $e');
    }
  }

  // ── Push: Turno ───────────────────────────────────────────────────────────

  Future<void> pushShift(ShiftModel shift) async {
    if (shift.id == null) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      await _db.collection('shifts').doc(shift.id).set({
        'name': shift.name,
        'color': shift.color.value,
        'from_minutes': shift.from.hour * 60 + shift.from.minute,
        'to_minutes': shift.to.hour * 60 + shift.to.minute,
        'euro_per_hour': shift.euroPerHour,
        'sort_order': shift.sortOrder,
        'owner_id': uid,
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      debugPrint('📤 Turno subido: ${shift.id}');
    } catch (e) {
      debugPrint('❌ Error push shift: $e');
    }
  }

  Future<void> deleteShift(String shiftId) async {
    try {
      await _db.collection('shifts').doc(shiftId).delete();
    } catch (e) {
      debugPrint('❌ Error delete shift Firebase: $e');
    }
  }

  // ── Push: Asignación de turno ─────────────────────────────────────────────

  Future<void> pushShiftAssignment(
    String id,
    String shiftId,
    DateTime date, {
    ShiftModel? shift,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      // Obtener UIDs con los que compartir turnos
      final sharedWith = await _getSharedWithUids(uid, 'turnos');
      final fromMin = shift != null
          ? shift.from.hour * 60 + shift.from.minute
          : 0;
      final toMin = shift != null ? shift.to.hour * 60 + shift.to.minute : 0;

      await _db.collection('shift_assignments').doc(id).set({
        'shift_id': shiftId,
        'date': Timestamp.fromDate(
          DateTime.utc(date.year, date.month, date.day),
        ),
        'owner_id': uid,
        'shared_with': sharedWith,
        // Datos desnormalizados para que el receptor pueda mostrarlo
        'shift_name': shift?.name ?? '',
        'shift_color': shift?.color.value ?? 0xFF2196F3,
        'shift_from_minutes': fromMin,
        'shift_to_minutes': toMin,
        'updated_at': FieldValue.serverTimestamp(),
      });
      debugPrint('📤 Asignación subida: $id → shared_with: $sharedWith');
    } catch (e) {
      debugPrint('❌ Error push shift_assignment: $e');
    }
  }

  Future<void> deleteShiftAssignment(String shiftId, DateTime date) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final snap = await _db
          .collection('shift_assignments')
          .where('shift_id', isEqualTo: shiftId)
          .where('owner_id', isEqualTo: uid)
          .where(
            'date',
            isEqualTo: Timestamp.fromDate(
              DateTime.utc(date.year, date.month, date.day),
            ),
          )
          .get();
      for (final doc in snap.docs) await doc.reference.delete();
    } catch (e) {
      debugPrint('❌ Error delete shift_assignment Firebase: $e');
    }
  }

  // ── Push: Checklist items ─────────────────────────────────────────────────

  Future<void> pushChecklistItems(
    String eventId,
    List<Map<String, dynamic>> items,
  ) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      // Borrar items anteriores del evento
      final old = await _db
          .collection('checklist_items')
          .where('event_id', isEqualTo: eventId)
          .get();
      final batch = _db.batch();
      for (final doc in old.docs) batch.delete(doc.reference);

      // Insertar nuevos
      for (final item in items) {
        final ref = _db.collection('checklist_items').doc();
        batch.set(ref, {...item, 'event_id': eventId, 'owner_id': uid});
      }
      await batch.commit();
      debugPrint('📤 Checklist subido para evento $eventId');
    } catch (e) {
      debugPrint('❌ Error push checklist: $e');
    }
  }

  Future<void> deleteChecklistForEvent(String eventId) async {
    try {
      final snap = await _db
          .collection('checklist_items')
          .where('event_id', isEqualTo: eventId)
          .get();
      final batch = _db.batch();
      for (final doc in snap.docs) batch.delete(doc.reference);
      await batch.commit();
    } catch (e) {
      debugPrint('❌ Error delete checklist Firebase: $e');
    }
  }

  // ── Push: Amigo ───────────────────────────────────────────────────────────

  Future<void> pushFriend(FriendModel friend) async {
    if (friend.id == null) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      await _db.collection('friends').doc(friend.id).set({
        'name': friend.name,
        'email': friend.email,
        'alias': friend.alias,
        'logo': friend.logo,
        'friend_uid': friend.firebaseUid,
        'owner_id': uid,
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      debugPrint('📤 Amigo subido: ${friend.id}');
    } catch (e) {
      debugPrint('❌ Error push friend: $e');
    }
  }

  Future<void> deleteFriend(String friendId) async {
    try {
      await _db.collection('friends').doc(friendId).delete();
    } catch (e) {
      debugPrint('❌ Error delete friend Firebase: $e');
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // LISTENER — Eventos compartidos en tiempo real
  // ══════════════════════════════════════════════════════════════════════════

  /// [onSharedEventReceived] se llama tras cada cambio de evento compartido.
  /// Úsalo para refrescar la UI (p.ej. recargar el mes en CalendarScreen).
  void startListening(String uid, {VoidCallback? onSharedEventReceived}) {
    stopListening(); // cancelar listeners anteriores

    // Escuchar eventos donde el usuario está en shared_with
    final sub = _db
        .collection('events')
        .where('shared_with', arrayContains: uid)
        .snapshots()
        .listen((snap) async {
          bool changed = false;
          for (final change in snap.docChanges) {
            final data = change.doc.data();
            if (data == null) continue;

            switch (change.type) {
              case DocumentChangeType.added:
              case DocumentChangeType.modified:
                await DBProvider.db.insertOrReplace(DBSchema.tableEvents, {
                  'id': change.doc.id,
                  'title': data['title'] ?? '',
                  'description': data['description'] ?? '',
                  'date': _msFromTs(data['date']) ?? 0,
                  'from_minutes': data['from_minutes'] ?? 0,
                  'to_minutes': data['to_minutes'] ?? 60,
                  'category': data['category'] ?? 'Evento',
                  'tipo': data['tipo'] ?? 'Otros',
                  'icon': data['icon'] ?? '',
                  'creator': data['creator'] ?? '',
                  'users': data['users'] ?? '',
                  'color': data['color'] ?? 4280391411,
                  'owner_id': data['owner_id'] ?? '',
                  'synced': 1,
                  'has_alarm': 0,
                  'alarm_at': null,
                  'has_notification': 0,
                  'notification_at': null,
                  'solo_para_mi': 0,
                });
                debugPrint(
                  '🔴 Evento compartido actualizado: ${change.doc.id}',
                );
                changed = true;
                break;
              case DocumentChangeType.removed:
                await DBProvider.db.delete(
                  DBSchema.tableEvents,
                  where: 'id = ?',
                  whereArgs: [change.doc.id],
                );
                debugPrint('🔴 Evento compartido eliminado: ${change.doc.id}');
                changed = true;
                break;
            }
          }
          // Notificar a la UI solo si hubo cambios reales
          if (changed) onSharedEventReceived?.call();
        }, onError: (e) => debugPrint('❌ Error listener eventos: $e'));

    _subscriptions.add(sub);

    // Listener para turnos compartidos
    final subShifts = _db
        .collection('shift_assignments')
        .where('shared_with', arrayContains: uid)
        .snapshots()
        .listen((snap) async {
          bool changed = false;
          for (final change in snap.docChanges) {
            final data = change.doc.data();
            if (data == null) continue;
            switch (change.type) {
              case DocumentChangeType.added:
              case DocumentChangeType.modified:
                await DBProvider.db
                    .insertOrReplace(DBSchema.tableShiftAssignments, {
                      'id': change.doc.id,
                      'shift_id': data['shift_id'] ?? '',
                      'date': _msFromTs(data['date']) ?? 0,
                      'owner_id': data['owner_id'] ?? '',
                      'shift_name': data['shift_name'] ?? '',
                      'shift_color': data['shift_color'] ?? 0xFF2196F3,
                      'shift_from_minutes': data['shift_from_minutes'] ?? 0,
                      'shift_to_minutes': data['shift_to_minutes'] ?? 0,
                    });
                changed = true;
                break;
              case DocumentChangeType.removed:
                await DBProvider.db.delete(
                  DBSchema.tableShiftAssignments,
                  where: 'id = ?',
                  whereArgs: [change.doc.id],
                );
                changed = true;
                break;
            }
          }
          if (changed) onSharedEventReceived?.call();
        }, onError: (e) => debugPrint('❌ Error listener turnos: $e'));

    _subscriptions.add(subShifts);
    debugPrint('👂 Listeners activos (eventos + turnos compartidos)');
  }

  void stopListening() {
    for (final sub in _subscriptions) sub.cancel();
    _subscriptions.clear();
    debugPrint('🔇 Listeners detenidos');
  }
}
