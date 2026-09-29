// lib/core/firebase_sync_service.dart
//
// Sincronización del CALENDARIO entre el móvil (SQLite) y Firebase.
//
// CAMBIOS (datos que se perdían al reinstalar la app):
//
//  1. Los eventos NUEVOS no se subían nunca. pushEvent() lee primero el
//     documento para comprobar si es de otra persona, y las reglas deniegan
//     leer un documento que aún no existe → error de permisos → el evento se
//     quedaba solo en el móvil. Ahora ese error se trata como "no existe" (las
//     reglas siguen impidiendo escribir en eventos ajenos) y además se corrige
//     la regla (ver firestore.rules).
//
//  2. Los eventos "Solo para mí" no se subían por diseño. Ahora se guarda una
//     copia PRIVADA en users/{uid}/private_events: nadie más puede leerla (lo
//     impiden las reglas), pero se recupera al reinstalar o cambiar de móvil.
//
//  3. Al reinstalar en iPhone la sesión se conserva (Keychain), así que no se
//     pasaba por la pantalla de login y nunca se descargaba nada. Ahora
//     ensureInitialSync() se llama al arrancar y restaura lo que falte.
//
//  4. pushPendingEvents() sube los eventos que se quedaron solo en local
//     (synced = 0) por el fallo del punto 1.
//
//  5. Además: el evento se sube con su categoría real (antes las
//     personalizadas se subían como "Evento"), se descargan también las
//     categorías propias, las asignaciones de turno completas y se vuelven a
//     programar las alarmas locales tras restaurar.

import 'dart:async';
import 'package:flutter/foundation.dart' show VoidCallback, debugPrint;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart' show Color;
import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;
import '../models/calendar_category.dart';
import '../models/event_item.dart';
import '../models/shift_model.dart';
import '../models/friend_model.dart';
import '../models/friend_request_model.dart';
import 'db_provider.dart';
import 'db_schema.dart';
import 'alarm_service.dart';

class FirebaseSyncService {
  FirebaseSyncService._();
  static final FirebaseSyncService instance = FirebaseSyncService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final List<StreamSubscription> _subscriptions = [];

  /// Las descargas van SIEMPRE al servidor: si no hay red fallan (y se
  /// reintentan en el siguiente arranque) en vez de devolver una caché vacía
  /// que se daría por buena.
  static const GetOptions _server = GetOptions(source: Source.server);

  Timestamp? _tsFromMs(int? ms) =>
      ms != null ? Timestamp.fromMillisecondsSinceEpoch(ms) : null;

  int? _msFromTs(dynamic ts) =>
      ts is Timestamp ? ts.millisecondsSinceEpoch : null;

  /// Copia privada de los eventos "Solo para mí" (solo la lee su dueño).
  CollectionReference<Map<String, dynamic>> _privateEvents(String uid) =>
      _db.collection('users').doc(uid).collection('private_events');

  // ══════════════════════════════════════════════════════════════════════════
  // ARRANQUE — restaurar y subir lo pendiente
  // ══════════════════════════════════════════════════════════════════════════

  bool _bootstrapping = false;

  /// Si esta base de datos local todavía no se ha sincronizado nunca con
  /// Firebase (app reinstalada, móvil nuevo…), descarga lo que falte.
  /// Solo AÑADE lo que no existe en local: no pisa nada.
  /// Devuelve true si ha restaurado datos.
  Future<bool> ensureInitialSync(String uid) async {
    if (_bootstrapping) return false;
    _bootstrapping = true;
    try {
      if (await _initialSyncDone(uid)) return false;
      debugPrint('🛟 BD local sin sincronizar: restaurando desde Firebase');
      return await pullAll(uid, onlyMissing: true);
    } finally {
      _bootstrapping = false;
    }
  }

  /// Sube los eventos propios que no llegaron a Firebase (synced = 0).
  /// Devuelve cuántos se han subido.
  Future<int> pushPendingEvents(String uid) async {
    try {
      final rows = await DBProvider.db.query(
        DBSchema.tableEvents,
        where:
            "synced = 0 AND (owner_id = ? OR owner_id IS NULL OR owner_id = '')",
        whereArgs: [uid],
      );
      var pushed = 0;
      for (final row in rows) {
        if (await _pushEventRow(uid, row)) pushed++;
      }
      if (pushed > 0) debugPrint('📤 $pushed eventos pendientes subidos');
      return pushed;
    } catch (e) {
      debugPrint('❌ pushPendingEvents: $e');
      return 0;
    }
  }

  Future<void> _ensureUsersTable() async {
    final db = await DBProvider.db.database;
    await db.execute(
      'CREATE TABLE IF NOT EXISTS ${DBSchema.tableUsers} '
      '(id TEXT PRIMARY KEY, email TEXT NOT NULL, name TEXT, last_sync INTEGER)',
    );
  }

  /// La marca vive en la propia BD local: si la BD se pierde (reinstalar),
  /// la marca se pierde con ella y se vuelve a restaurar.
  Future<bool> _initialSyncDone(String uid) async {
    try {
      await _ensureUsersTable();
      final rows = await DBProvider.db.query(
        DBSchema.tableUsers,
        where: 'id = ?',
        whereArgs: [uid],
        limit: '1',
      );
      return rows.isNotEmpty && ((rows.first['last_sync'] as int?) ?? 0) > 0;
    } catch (e) {
      debugPrint('⚠️ No se pudo leer la marca de sincronización: $e');
      return false;
    }
  }

  Future<void> _markInitialSyncDone(String uid) async {
    try {
      await _ensureUsersTable();
      final user = FirebaseAuth.instance.currentUser;
      await DBProvider.db.insertOrReplace(DBSchema.tableUsers, {
        'id': uid,
        'email': user?.email ?? '',
        'name': user?.displayName ?? '',
        'last_sync': DateTime.now().millisecondsSinceEpoch,
      });
    } catch (e) {
      debugPrint('⚠️ No se pudo guardar la marca de sincronización: $e');
    }
  }

  /// Inserta filas: reemplazando (login) o solo las que falten (arranque).
  Future<void> _insertRows(
    String table,
    List<Map<String, dynamic>> rows, {
    required bool onlyMissing,
  }) async {
    if (rows.isEmpty) return;
    if (!onlyMissing) {
      await DBProvider.db.batchInsert(table, rows);
      return;
    }
    final db = await DBProvider.db.database;
    final batch = db.batch();
    for (final r in rows) {
      batch.insert(table, r, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    await batch.commit(noResult: true);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // PULL — Firebase → SQLite  (login y arranque)
  // ══════════════════════════════════════════════════════════════════════════

  /// Descarga todo lo del usuario. [onlyMissing] = true no pisa filas que ya
  /// existan en local. Devuelve true si todo se ha descargado bien.
  Future<bool> pullAll(String uid, {bool onlyMissing = false}) async {
    debugPrint('🔄 Iniciando sync pull para uid=$uid');
    final results = await Future.wait<bool>([
      _pullEvents(uid, onlyMissing),
      _pullShifts(uid, onlyMissing),
      _pullShiftAssignments(uid, onlyMissing),
      _pullFriends(uid, onlyMissing),
      _pullOwnCategories(uid, onlyMissing),
    ]);
    await pullAcceptedRequests(uid);

    final ok = results.every((r) => r);
    if (ok) {
      await _markInitialSyncDone(uid);
      // Las alarmas locales no viajan con los datos (y el logout las borra):
      // se vuelven a programar las que sigan en el futuro.
      await _rescheduleOwnAlarms(uid);
    }
    debugPrint(ok ? '✅ Sync pull completado' : '⚠️ Sync pull incompleto');
    return ok;
  }

  // ── Pull: Eventos (compartidos + privados) + checklist embebido ───────────

  Future<bool> _pullEvents(String uid, bool onlyMissing) async {
    try {
      final own = await _db
          .collection('events')
          .where('owner_id', isEqualTo: uid)
          .get(_server);
      final shared = await _db
          .collection('events')
          .where('shared_with', arrayContains: uid)
          .get(_server);
      final private = await _privateEvents(uid).get(_server);

      final eventRows = <Map<String, dynamic>>[];
      final checklistRows = <Map<String, dynamic>>[];

      void addDoc(
        QueryDocumentSnapshot<Map<String, dynamic>> d, {
        required bool isPrivate,
      }) {
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
          'owner_id': isPrivate ? uid : (data['owner_id'] ?? uid),
          'synced': 1,
          'has_alarm': (data['has_alarm'] ?? false) ? 1 : 0,
          'alarm_at': _msFromTs(data['alarm_at']),
          'has_notification': (data['has_notification'] ?? false) ? 1 : 0,
          'notification_at': _msFromTs(data['notification_at']),
          'solo_para_mi': isPrivate || (data['solo_para_mi'] ?? false) ? 1 : 0,
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

      final seen = <String>{};
      for (final d in [...own.docs, ...shared.docs]) {
        if (seen.add(d.id)) addDoc(d, isPrivate: false);
      }
      for (final d in private.docs) {
        if (seen.add(d.id)) addDoc(d, isPrivate: true);
      }

      await _insertRows(
        DBSchema.tableEvents,
        eventRows,
        onlyMissing: onlyMissing,
      );
      await _insertRows(
        DBSchema.tableChecklist,
        checklistRows,
        onlyMissing: onlyMissing,
      );
      debugPrint(
        '📥 ${eventRows.length} eventos (${private.docs.length} privados) + '
        '${checklistRows.length} checklist items',
      );
      return true;
    } catch (e) {
      debugPrint('❌ Error pull events: $e');
      return false;
    }
  }

  // ── Pull: Turnos ──────────────────────────────────────────────────────────

  Future<bool> _pullShifts(String uid, bool onlyMissing) async {
    try {
      final snap = await _db
          .collection('shifts')
          .where('owner_id', isEqualTo: uid)
          .get(_server);
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
      await _insertRows(DBSchema.tableShifts, rows, onlyMissing: onlyMissing);
      debugPrint('📥 ${rows.length} turnos');
      return true;
    } catch (e) {
      debugPrint('❌ Error pull shifts: $e');
      return false;
    }
  }

  // ── Pull: Asignaciones (ahora con todos sus campos) ───────────────────────

  Future<bool> _pullShiftAssignments(String uid, bool onlyMissing) async {
    try {
      final snap = await _db
          .collection('shift_assignments')
          .where('owner_id', isEqualTo: uid)
          .get(_server);
      final rows = snap.docs.map((d) {
        final data = d.data();
        return {
          'id': d.id,
          'shift_id': data['shift_id'] ?? '',
          'date': _msFromTs(data['date']) ?? 0,
          'owner_id': data['owner_id'] ?? uid,
          'shift_name': data['shift_name'] ?? '',
          'shift_color': data['shift_color'] ?? 0xFF2196F3,
          'shift_from_minutes': data['shift_from_minutes'] ?? 0,
          'shift_to_minutes': data['shift_to_minutes'] ?? 0,
        };
      }).toList();
      await _insertRows(
        DBSchema.tableShiftAssignments,
        rows,
        onlyMissing: onlyMissing,
      );
      debugPrint('📥 ${rows.length} asignaciones de turno');
      return true;
    } catch (e) {
      debugPrint('❌ Error pull shift_assignments: $e');
      return false;
    }
  }

  // ── Pull: Amigos ──────────────────────────────────────────────────────────

  Future<bool> _pullFriends(String uid, bool onlyMissing) async {
    try {
      final snap = await _db
          .collection('friends')
          .where('owner_id', isEqualTo: uid)
          .get(_server);
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
      await _insertRows(DBSchema.tableFriends, rows, onlyMissing: onlyMissing);
      return true;
    } catch (e) {
      debugPrint('❌ Error pull friends: $e');
      return false;
    }
  }

  // ── Pull: Categorías PROPIAS (antes solo se traían las compartidas) ───────

  Future<bool> _pullOwnCategories(String uid, bool onlyMissing) async {
    try {
      final snap = await _db
          .collection('calendar_categories')
          .where('owner_id', isEqualTo: uid)
          .get(_server);
      final rows = snap.docs
          .map(
            (d) => CalendarCategory.fromFirestore(
              d.data(),
            ).copyWith(synced: true).toMap(),
          )
          .toList();
      await _insertRows(
        DBSchema.tableCalendarCategories,
        rows,
        onlyMissing: onlyMissing,
      );
      debugPrint('📥 ${rows.length} categorías propias');
      return true;
    } catch (e) {
      debugPrint('❌ Error pull categorías propias: $e');
      return false;
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

  // ── Alarmas locales tras restaurar ────────────────────────────────────────

  Future<void> _rescheduleOwnAlarms(String uid) async {
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final rows = await DBProvider.db.query(
        DBSchema.tableEvents,
        where:
            "(owner_id = ? OR owner_id IS NULL OR owner_id = '') AND "
            '((has_alarm = 1 AND alarm_at > ?) OR '
            '(has_notification = 1 AND notification_at > ?))',
        whereArgs: [uid, now, now],
      );
      for (final r in rows) {
        final id = r['id'] as String;
        final title = (r['title'] as String?) ?? '';
        final desc = (r['description'] as String?) ?? '';
        final alarmAt = r['alarm_at'] as int?;
        final notifAt = r['notification_at'] as int?;
        if (r['has_alarm'] == 1 && alarmAt != null && alarmAt > now) {
          await AlarmService.instance.schedule(
            eventId: id,
            title: '⏰ $title',
            body: desc.isNotEmpty ? desc : 'Alarma de evento',
            fireAt: DateTime.fromMillisecondsSinceEpoch(alarmAt),
            type: AlarmType.alarm,
          );
        }
        if (r['has_notification'] == 1 && notifAt != null && notifAt > now) {
          await AlarmService.instance.schedule(
            eventId: id,
            title: '🔔 $title',
            body: desc.isNotEmpty ? desc : 'Recordatorio',
            fireAt: DateTime.fromMillisecondsSinceEpoch(notifAt),
            type: AlarmType.notification,
          );
        }
      }
      if (rows.isNotEmpty) {
        debugPrint('⏰ ${rows.length} eventos con alarma reprogramados');
      }
    } catch (e) {
      debugPrint('⚠️ No se pudieron reprogramar las alarmas: $e');
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // PUSH — SQLite → Firebase
  // ══════════════════════════════════════════════════════════════════════════

  // ── Push: Evento ──────────────────────────────────────────────────────────

  Future<void> pushEvent(EventItem event, DateTime date) async {
    if (event.id == null) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final dayUtc = DateTime.utc(date.year, date.month, date.day);
    await _pushEventFields(
      uid: uid,
      eventId: event.id!,
      soloParaMi: event.soloParaMi,
      // La categoría para decidir con quién se comparte sigue siendo la misma
      // que antes (no cambia el comportamiento de compartir).
      shareCategory: event.category.name,
      fields: {
        'title': event.title,
        'description': event.description,
        'date': Timestamp.fromDate(dayUtc),
        'from_minutes': event.from.hour * 60 + event.from.minute,
        'to_minutes': event.to.hour * 60 + event.to.minute,
        // CORREGIDO: la key real (las personalizadas se subían como "Evento").
        'category': event.categoryKey ?? event.category.name,
        'tipo': event.tipo.name,
        'icon': event.icon,
        'color': event.color.value,
        'creator': event.creator,
        'users': event.users.join('|'),
        'has_alarm': event.hasAlarm,
        'alarm_at': _tsFromMs(event.alarmAt?.millisecondsSinceEpoch),
        'has_notification': event.hasNotification,
        'notification_at': _tsFromMs(
          event.notificationAt?.millisecondsSinceEpoch,
        ),
        // checklist_items se actualiza justo después con pushChecklistToEvent
      },
    );
  }

  /// Sube un evento a partir de su fila de SQLite (eventos pendientes).
  /// Incluye su checklist en la misma escritura.
  Future<bool> _pushEventRow(String uid, Map<String, dynamic> row) async {
    final id = row['id'] as String?;
    if (id == null || id.isEmpty) return false;

    final checklist = await DBProvider.db.query(
      DBSchema.tableChecklist,
      where: 'event_id = ?',
      whereArgs: [id],
    );
    final rawCategory = (row['category'] as String?) ?? 'Evento';

    return _pushEventFields(
      uid: uid,
      eventId: id,
      soloParaMi: row['solo_para_mi'] == 1,
      shareCategory: _enumCategoryName(rawCategory),
      fields: {
        'title': row['title'] ?? '',
        'description': row['description'] ?? '',
        'date': Timestamp.fromMillisecondsSinceEpoch(
          (row['date'] as int?) ?? 0,
        ),
        'from_minutes': row['from_minutes'] ?? 0,
        'to_minutes': row['to_minutes'] ?? 60,
        'category': rawCategory,
        'tipo': row['tipo'] ?? 'Otros',
        'icon': row['icon'] ?? '',
        'color': row['color'] ?? 4280391411,
        'creator': row['creator'] ?? '',
        'users': row['users'] ?? '',
        'has_alarm': row['has_alarm'] == 1,
        'alarm_at': _tsFromMs(row['alarm_at'] as int?),
        'has_notification': row['has_notification'] == 1,
        'notification_at': _tsFromMs(row['notification_at'] as int?),
        if (checklist.isNotEmpty)
          'checklist_items': {
            for (final c in checklist)
              c['id'] as String: {
                'text': c['text'] ?? '',
                'is_checked': c['is_checked'] == 1,
                'position': c['position'] ?? 0,
              },
          },
      },
    );
  }

  /// Nombre del enum Category para una key (las personalizadas → 'Evento'),
  /// igual que hace EventRepository al leer.
  String _enumCategoryName(String raw) {
    for (final c in Category.values) {
      if (c.name == raw) return c.name;
    }
    return Category.Evento.name;
  }

  /// Escritura común de un evento. Devuelve true si ha llegado a Firebase.
  Future<bool> _pushEventFields({
    required String uid,
    required String eventId,
    required bool soloParaMi,
    required String shareCategory,
    required Map<String, dynamic> fields,
  }) async {
    try {
      final ref = _db.collection('events').doc(eventId);
      final privRef = _privateEvents(uid).doc(eventId);

      // ¿Existe ya y es de OTRA persona? Entonces no se sube: un receptor no
      // puede editar eventos ajenos (lo impiden también las reglas).
      //
      // CORREGIDO: si el evento es NUEVO, leerlo daba "permission-denied"
      // (las reglas no dejaban leer un documento inexistente) y el evento no
      // se subía nunca. Ese error equivale a "no existe o no es mío": las
      // reglas deciden al escribir.
      DocumentSnapshot<Map<String, dynamic>>? existing;
      try {
        existing = await ref.get();
      } on FirebaseException catch (e) {
        if (e.code != 'permission-denied') rethrow;
        existing = null;
      }
      final bool existsShared = existing?.exists ?? false;
      if (existsShared) {
        final ownerId = existing!.data()?['owner_id'] as String?;
        if (ownerId != null && ownerId.isNotEmpty && ownerId != uid) {
          debugPrint('⛔ Evento $eventId es de otro usuario: no se sube');
          return false;
        }
      }

      if (soloParaMi) {
        // Copia de seguridad PRIVADA: solo la puede leer su dueño.
        await privRef.set({
          ...fields,
          'owner_id': uid,
          'solo_para_mi': true,
          'updated_at': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        // Si antes era un evento compartido, deja de estarlo para los demás.
        // (Antes se quedaba visible para ellos al marcarlo "Solo para mí".)
        if (existsShared) await ref.delete();
        debugPrint('🔒 Evento privado respaldado: $eventId');
      } else {
        final sharedWithUids = await _getSharedWithUids(uid, shareCategory);
        await ref.set({
          ...fields,
          'owner_id': uid,
          'shared_with': sharedWithUids,
          'solo_para_mi': false,
          'updated_at': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        // Si antes era "Solo para mí", sobra la copia privada.
        unawaited(privRef.delete().catchError((_) {}));
        debugPrint('📤 Evento: $eventId → shared_with: $sharedWithUids');
      }

      await _markEventSynced(eventId);
      return true;
    } catch (e) {
      debugPrint('❌ Error push event $eventId: $e');
      return false;
    }
  }

  Future<void> _markEventSynced(String eventId) async {
    try {
      final db = await DBProvider.db.database;
      await db.update(
        DBSchema.tableEvents,
        {'synced': 1},
        where: 'id = ?',
        whereArgs: [eventId],
      );
    } catch (e) {
      debugPrint('⚠️ No se pudo marcar el evento como subido: $e');
    }
  }

  /// Actualiza un campo del evento en su sitio: compartido o, si no existe
  /// ahí, en la copia privada ("Solo para mí").
  Future<void> _updateEventDoc(
    String eventId,
    Map<String, dynamic> data,
  ) async {
    try {
      await _db.collection('events').doc(eventId).update(data);
    } on FirebaseException catch (e) {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null ||
          (e.code != 'not-found' && e.code != 'permission-denied')) {
        rethrow;
      }
      await _privateEvents(uid).doc(eventId).update(data);
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
      await _updateEventDoc(eventId, {
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
      await _updateEventDoc(eventId, {
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
    // También la copia privada, si la hubiera.
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await _privateEvents(uid).doc(eventId).delete();
    } catch (e) {
      debugPrint('❌ Error delete private event: $e');
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
                // Conservamos los campos del recordatorio (has_notification,
                // notification_at, has_alarm, alarm_at). El push del
                // recordatorio compartido lo envía el Cloud Function
                // reminderDispatcher, NO una notificación local, para evitar
                // notificaciones duplicadas.
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
                  'has_alarm': (data['has_alarm'] ?? false) ? 1 : 0,
                  'alarm_at': _msFromTs(data['alarm_at']),
                  'has_notification': (data['has_notification'] ?? false)
                      ? 1
                      : 0,
                  'notification_at': _msFromTs(data['notification_at']),
                  'solo_para_mi': (data['solo_para_mi'] ?? false) ? 1 : 0,
                });

                await _saveEmbeddedChecklist(
                  change.doc.id,
                  data['checklist_items'],
                );

                changed = true;
                break;

              case DocumentChangeType.removed:
                // Cancela cualquier alarma local que pudiera haber quedado de
                // versiones anteriores (inofensivo si no existe ninguna).
                await AlarmService.instance.cancelAll(change.doc.id);
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

    // Listener sobre los eventos PROPIOS para detectar cambios hechos por
    // otros usuarios (p.ej. B marca/desmarca un checklist en un evento de A).
    // Sin este listener, A no se entera de los cambios que B hace en tiempo real.
    final subOwnEvents = _db
        .collection('events')
        .where('owner_id', isEqualTo: uid)
        .snapshots()
        .listen((snap) async {
          bool changed = false;
          for (final change in snap.docChanges) {
            if (change.type != DocumentChangeType.modified) continue;
            final data = change.doc.data();
            if (data == null) continue;
            // Solo actualizamos checklist embebido — el evento en sí ya está
            // en SQLite y no necesita reescribirse completo.
            await _saveEmbeddedChecklist(
              change.doc.id,
              data['checklist_items'],
            );
            changed = true;
          }
          if (changed) onSharedEventReceived?.call();
        }, onError: (e) => debugPrint('❌ Error listener own events: $e'));

    _subscriptions.add(subOwnEvents);

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
