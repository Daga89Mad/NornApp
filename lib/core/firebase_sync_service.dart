// lib/core/firebase_sync_service.dart
//
// ARQUITECTURA DEL CHECKLIST (v2 - definitiva):
//  Los items se guardan DENTRO del documento del evento en Firestore
//  como campo Map: "checklist_items": { itemId: {text, is_checked, position} }
//
//  Ventajas vs colección separada:
//   ✅ Sin race condition (items viajan con el evento)
//   ✅ Sin índice extra en Firestore
//   ✅ El listener ya trae los items, sin consulta adicional
//   ✅ Toggle actualiza events/{id}.checklist_items.{itemId}.is_checked

import 'dart:async';
import 'package:flutter/foundation.dart' show VoidCallback, debugPrint;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart' show Color;
import '../models/event_item.dart';
import '../models/shift_model.dart';
import '../models/friend_model.dart';
import '../models/friend_request_model.dart';
import 'db_provider.dart';
import 'db_schema.dart';

class FirebaseSyncService {
  FirebaseSyncService._();
  static final FirebaseSyncService instance = FirebaseSyncService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final List<StreamSubscription> _subscriptions = [];

  Timestamp? _tsFromMs(int? ms) =>
      ms != null ? Timestamp.fromMillisecondsSinceEpoch(ms) : null;

  int? _msFromTs(dynamic ts) =>
      ts is Timestamp ? ts.millisecondsSinceEpoch : null;

  // ══════════════════════════════════════════════════════════════════════════
  // PULL — Firebase → SQLite  (login)
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> pullAll(String uid) async {
    debugPrint('🔄 Iniciando sync pull para uid=$uid');
    await Future.wait([
      _pullEvents(uid),
      _pullShifts(uid),
      _pullShiftAssignments(uid),
      _pullFriends(uid),
      pullAcceptedRequests(uid),
    ]);
    debugPrint('✅ Sync pull completado');
  }

  // ── Pull: Eventos + checklist embebido ────────────────────────────────────

  Future<void> _pullEvents(String uid) async {
    try {
      final own = await _db
          .collection('events')
          .where('owner_id', isEqualTo: uid)
          .get();
      final shared = await _db
          .collection('events')
          .where('shared_with', arrayContains: uid)
          .get();

      final allDocs = {...own.docs, ...shared.docs};
      if (allDocs.isEmpty) return;

      final eventRows = <Map<String, dynamic>>[];
      final checklistRows = <Map<String, dynamic>>[];

      for (final d in allDocs) {
        final data = d.data();
        eventRows.add({
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
        });

        // Extraer checklist embebido en el doc del evento
        final embedded = data['checklist_items'] as Map<String, dynamic>? ?? {};
        for (final entry in embedded.entries) {
          final item = entry.value as Map<String, dynamic>;
          checklistRows.add({
            'id': entry.key,
            'event_id': d.id,
            'text': item['text'] ?? '',
            'is_checked': (item['is_checked'] ?? false) ? 1 : 0,
            'position': item['position'] ?? 0,
          });
        }
      }

      await DBProvider.db.batchInsert(DBSchema.tableEvents, eventRows);
      if (checklistRows.isNotEmpty) {
        await DBProvider.db.batchInsert(DBSchema.tableChecklist, checklistRows);
      }
      debugPrint(
        '📥 ${eventRows.length} eventos + ${checklistRows.length} checklist items',
      );
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
      debugPrint('📥 ${rows.length} turnos');
    } catch (e) {
      debugPrint('❌ Error pull shifts: $e');
    }
  }

  // ── Pull: Asignaciones ────────────────────────────────────────────────────

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
    } catch (e) {
      debugPrint('❌ Error pull shift_assignments: $e');
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
    } catch (e) {
      debugPrint('❌ Error pull friends: $e');
    }
  }

  // ── Pull: Solicitudes aceptadas ───────────────────────────────────────────

  Future<void> pullAcceptedRequests(String uid) async {
    try {
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

        final profileSnap = await _db
            .collection('user_profiles')
            .doc(toUid)
            .get();
        final toName = (profileSnap.data()?['name'] as String?) ?? toEmail;

        final existing = await DBProvider.db.query(
          DBSchema.tableFriends,
          where: 'firebase_uid = ?',
          whereArgs: [toUid],
        );
        if (existing.isEmpty) {
          final logo = (data['from_logo'] as String?)?.isNotEmpty == true
              ? data['from_logo'] as String
              : '😊';
          await DBProvider.db.insertOrReplace(DBSchema.tableFriends, {
            'id': '${DateTime.now().millisecondsSinceEpoch}_$toUid',
            'name': toName,
            'email': toEmail,
            'alias': '',
            'logo': logo,
            'firebase_uid': toUid,
          });
        }
        await doc.reference.update({'status': 'synced'});
      }
    } catch (e) {
      debugPrint('❌ Error pull accepted requests: $e');
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // PUSH — SQLite → Firebase
  // ══════════════════════════════════════════════════════════════════════════

  // ── Push: Evento ──────────────────────────────────────────────────────────

  Future<void> pushEvent(EventItem event, DateTime date) async {
    if (event.id == null || event.soloParaMi) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
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
        // checklist_items se actualiza justo después con pushChecklistToEvent
      }, SetOptions(merge: true));

      debugPrint('📤 Evento: ${event.id} → shared_with: $sharedWithUids');
    } catch (e) {
      debugPrint('❌ Error push event: $e');
    }
  }

  // ── Push: Checklist embebido en el evento ─────────────────────────────────
  //
  // Llama a este método DESPUÉS de pushEvent.
  // Usa merge:false en checklist_items para reemplazar la lista completa.

  Future<void> pushChecklistToEvent(
    String eventId,
    List<Map<String, dynamic>> items,
  ) async {
    try {
      final Map<String, dynamic> checklistMap = {};
      for (final item in items) {
        final id = item['id'] as String;
        checklistMap[id] = {
          'text': item['text'],
          'is_checked': false,
          'position': item['position'],
        };
      }

      // update() en vez de set() para no sobreescribir shared_with, etc.
      await _db.collection('events').doc(eventId).update({
        'checklist_items': checklistMap,
        'updated_at': FieldValue.serverTimestamp(),
      });

      debugPrint(
        '📤 Checklist embebido en evento $eventId (${items.length} items)',
      );
    } catch (e) {
      debugPrint('❌ Error push checklist to event: $e');
    }
  }

  // ── Push: Toggle check de un item ─────────────────────────────────────────
  //
  // Actualiza SOLO el campo is_checked dentro del mapa.
  // El receptor lo recibe via el listener de eventos (sin colección extra).

  Future<void> pushChecklistItemChecked(
    String eventId,
    String itemId,
    bool isChecked,
  ) async {
    try {
      await _db.collection('events').doc(eventId).update({
        'checklist_items.$itemId.is_checked': isChecked,
        'updated_at': FieldValue.serverTimestamp(),
      });
      debugPrint('📤 Check: evento=$eventId item=$itemId → $isChecked');
    } catch (e) {
      debugPrint('❌ Error push check: $e');
    }
  }

  Future<void> deleteEvent(String eventId) async {
    try {
      await _db.collection('events').doc(eventId).delete();
    } catch (e) {
      debugPrint('❌ Error delete event: $e');
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
    } catch (e) {
      debugPrint('❌ Error push shift: $e');
    }
  }

  Future<void> deleteShift(String shiftId) async {
    try {
      await _db.collection('shifts').doc(shiftId).delete();
    } catch (e) {
      debugPrint('❌ Error delete shift: $e');
    }
  }

  Future<void> pushShiftAssignment(
    String id,
    String shiftId,
    DateTime date, {
    ShiftModel? shift,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
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
        'shift_name': shift?.name ?? '',
        'shift_color': shift?.color.value ?? 0xFF2196F3,
        'shift_from_minutes': fromMin,
        'shift_to_minutes': toMin,
        'updated_at': FieldValue.serverTimestamp(),
      });
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
      for (final doc in snap.docs) {
        await doc.reference.delete();
      }
    } catch (e) {
      debugPrint('❌ Error delete shift_assignment: $e');
    }
  }

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
    } catch (e) {
      debugPrint('❌ Error push friend: $e');
    }
  }

  Future<void> deleteFriend(String friendId) async {
    try {
      await _db.collection('friends').doc(friendId).delete();
    } catch (e) {
      debugPrint('❌ Error delete friend: $e');
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // LISTENER — Tiempo real
  // ══════════════════════════════════════════════════════════════════════════

  void startListening(String uid, {VoidCallback? onSharedEventReceived}) {
    stopListening();

    // Listener de eventos compartidos.
    // Cada snapshot ya trae checklist_items embebido → sin consulta extra.
    final subEvents = _db
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
                // Checklist embebido → se guarda directamente del snapshot
                await _saveEmbeddedChecklist(
                  change.doc.id,
                  data['checklist_items'],
                );
                changed = true;
                break;

              case DocumentChangeType.removed:
                await DBProvider.db.delete(
                  DBSchema.tableEvents,
                  where: 'id = ?',
                  whereArgs: [change.doc.id],
                );
                await DBProvider.db.delete(
                  DBSchema.tableChecklist,
                  where: 'event_id = ?',
                  whereArgs: [change.doc.id],
                );
                changed = true;
                break;
            }
          }
          if (changed) onSharedEventReceived?.call();
        }, onError: (e) => debugPrint('❌ Error listener eventos: $e'));

    _subscriptions.add(subEvents);

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
    debugPrint('👂 Listeners activos');
  }

  Future<void> _saveEmbeddedChecklist(String eventId, dynamic rawItems) async {
    try {
      final itemsMap = rawItems as Map<String, dynamic>? ?? {};
      if (itemsMap.isEmpty) return;

      await DBProvider.db.delete(
        DBSchema.tableChecklist,
        where: 'event_id = ?',
        whereArgs: [eventId],
      );

      final rows = itemsMap.entries.map((e) {
        final item = e.value as Map<String, dynamic>;
        return {
          'id': e.key,
          'event_id': eventId,
          'text': item['text'] ?? '',
          'is_checked': (item['is_checked'] ?? false) ? 1 : 0,
          'position': item['position'] ?? 0,
        };
      }).toList();

      await DBProvider.db.batchInsert(DBSchema.tableChecklist, rows);
      debugPrint('📥 ${rows.length} checklist items → evento $eventId');
    } catch (e) {
      debugPrint('❌ Error guardando checklist embebido: $e');
    }
  }

  void stopListening() {
    for (final sub in _subscriptions) sub.cancel();
    _subscriptions.clear();
  }

  Future<List<String>> _getSharedWithUids(
    String uid,
    String categoryName,
  ) async {
    try {
      final snap = await _db
          .collection('calendar_shares')
          .where('from_uid', isEqualTo: uid)
          .get();
      final result = <String>[];
      for (final doc in snap.docs) {
        final data = doc.data();
        final toUid = data['to_uid'] as String? ?? '';
        final categories = List<String>.from(data['categories'] ?? []);
        if (toUid.isEmpty) continue;
        final catLower = categoryName.toLowerCase();
        final matches = categories.any((c) {
          final cl = c.toLowerCase();
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
      debugPrint('⚠️ Error calendar_shares: $e');
      return [];
    }
  }
}
