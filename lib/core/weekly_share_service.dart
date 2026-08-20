// lib/core/weekly_share_service.dart
//
// Gestiona el compartir menús semanales y tareas semanales con amigos.
//
// Arquitectura:
//   · 'weekly_shares/{myUid}_{friendUid}' = { from_uid, to_uid, types: ['menus','tasks'] }
//   · Los documentos de weekly_menus/weekly_tasks tienen campo 'shared_with': [uid,...]
//   · Cuando A comparte con B, todos los docs existentes de A se actualizan con B en shared_with
//   · Los nuevos docs que guarda A también incluyen shared_with gracias al repositorio
//   · B tiene un listener en tiempo real sobre docs donde shared_with contains B
//   · Además se puede compartir UN SOLO item con un amigo (shareSingleItem).

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../models/friend_model.dart';
import 'db_provider.dart';
import 'db_schema.dart';

class WeeklyShareService {
  WeeklyShareService._();
  static final WeeklyShareService instance = WeeklyShareService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  static const String _sharesCol = 'weekly_shares';
  static const String _menusCol = 'weekly_menus';
  static const String _tasksCol = 'weekly_tasks';

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';
  final List<StreamSubscription> _subscriptions = [];

  String _colFor(String type) => type == 'menus' ? _menusCol : _tasksCol;
  String _tableFor(String type) =>
      type == 'menus' ? DBSchema.tableWeeklyMenus : DBSchema.tableWeeklyTasks;

  // ══════════════════════════════════════════════════════════════════════════
  // COMPARTIR (global: toda mi semana con un amigo)
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> shareWithFriends({
    required List<String> types,
    required List<FriendModel> friends,
  }) async {
    if (_uid.isEmpty || types.isEmpty || friends.isEmpty) return;

    final friendUids = friends
        .where((f) => f.firebaseUid != null)
        .map((f) => f.firebaseUid!)
        .toList();
    if (friendUids.isEmpty) return;

    for (final fUid in friendUids) {
      await _db.collection(_sharesCol).doc('${_uid}_$fUid').set({
        'from_uid': _uid,
        'to_uid': fUid,
        'types': types,
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    if (types.contains('menus')) {
      await _addSharedWithToExisting(_menusCol, friendUids);
    }
    if (types.contains('tasks')) {
      await _addSharedWithToExisting(_tasksCol, friendUids);
    }

    debugPrint('📤 Weekly share: tipos=$types con ${friendUids.length} amigos');
  }

  Future<void> unshareWithFriends({
    required List<String> types,
    required List<FriendModel> friends,
  }) async {
    if (_uid.isEmpty || friends.isEmpty) return;

    final friendUids = friends
        .where((f) => f.firebaseUid != null)
        .map((f) => f.firebaseUid!)
        .toList();
    if (friendUids.isEmpty) return;

    for (final fUid in friendUids) {
      final docRef = _db.collection(_sharesCol).doc('${_uid}_$fUid');
      final snap = await docRef.get();
      if (!snap.exists) continue;

      final currentTypes = List<String>.from(snap.data()?['types'] ?? []);
      for (final t in types) currentTypes.remove(t);

      if (currentTypes.isEmpty) {
        await docRef.delete();
      } else {
        await docRef.update({'types': currentTypes});
      }
    }

    if (types.contains('menus')) {
      await _removeSharedWithFromExisting(_menusCol, friendUids);
    }
    if (types.contains('tasks')) {
      await _removeSharedWithFromExisting(_tasksCol, friendUids);
    }

    debugPrint(
      '🚫 Weekly unshare: tipos=$types con ${friendUids.length} amigos',
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // COMPARTIR UN SOLO ITEM (menú o tarea concreta) CON UN AMIGO
  // ══════════════════════════════════════════════════════════════════════════

  /// Añade [friendUid] al shared_with de un único documento (menú o tarea)
  /// tanto en Firebase como en local. No toca la configuración global.
  Future<void> shareSingleItem({
    required String type, // 'menus' | 'tasks'
    required String docId,
    required String friendUid,
  }) async {
    if (_uid.isEmpty || friendUid.isEmpty || docId.isEmpty) return;
    try {
      await _db.collection(_colFor(type)).doc(docId).set({
        'shared_with': FieldValue.arrayUnion([friendUid]),
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('❌ shareSingleItem Firebase: $e');
    }
    await _mergeLocalSharedWith(type, docId, add: [friendUid]);
    debugPrint('📤 Item $docId compartido con $friendUid');
  }

  /// Quita [friendUid] del shared_with de un único documento.
  Future<void> unshareSingleItem({
    required String type,
    required String docId,
    required String friendUid,
  }) async {
    if (_uid.isEmpty || friendUid.isEmpty || docId.isEmpty) return;
    try {
      await _db.collection(_colFor(type)).doc(docId).set({
        'shared_with': FieldValue.arrayRemove([friendUid]),
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('❌ unshareSingleItem Firebase: $e');
    }
    await _mergeLocalSharedWith(type, docId, remove: [friendUid]);
    debugPrint('🚫 Item $docId dejado de compartir con $friendUid');
  }

  /// Devuelve el set de UIDs con los que está compartido un item (según local).
  Future<Set<String>> getSharedUidsForItem({
    required String type,
    required String docId,
  }) async {
    final rows = await DBProvider.db.query(
      _tableFor(type),
      where: 'id = ?',
      whereArgs: [docId],
      limit: '1',
    );
    if (rows.isEmpty) return {};
    return parseUids(rows.first['shared_with'] as String? ?? '');
  }

  Future<void> _mergeLocalSharedWith(
    String type,
    String docId, {
    List<String> add = const [],
    List<String> remove = const [],
  }) async {
    final rows = await DBProvider.db.query(
      _tableFor(type),
      where: 'id = ?',
      whereArgs: [docId],
      limit: '1',
    );
    if (rows.isEmpty) return;
    final row = Map<String, dynamic>.from(rows.first);
    final set = parseUids(row['shared_with'] as String? ?? '');
    set.addAll(add);
    set.removeAll(remove);
    row['shared_with'] = uidsToJson(set);
    row['synced'] = 1;
    await DBProvider.db.insertOrReplace(_tableFor(type), row);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // CONSULTA DE CONFIGURACIÓN ACTUAL
  // ══════════════════════════════════════════════════════════════════════════

  Future<List<Map<String, dynamic>>> getCurrentShares(
    List<FriendModel> friends,
  ) async {
    if (_uid.isEmpty) return [];
    try {
      final snap = await _db
          .collection(_sharesCol)
          .where('from_uid', isEqualTo: _uid)
          .get();

      final result = <Map<String, dynamic>>[];
      for (final doc in snap.docs) {
        final data = doc.data();
        final toUid = data['to_uid'] as String? ?? '';
        final types = List<String>.from(data['types'] ?? []);
        final friend = friends.firstWhere(
          (f) => f.firebaseUid == toUid,
          orElse: () => FriendModel(name: toUid, email: '', firebaseUid: toUid),
        );
        result.add({'friend': friend, 'types': types});
      }
      return result;
    } catch (e) {
      debugPrint('❌ Error getCurrentShares: $e');
      return [];
    }
  }

  Future<List<String>> getSharedUidsForType(String type) async {
    if (_uid.isEmpty) return [];
    try {
      final snap = await _db
          .collection(_sharesCol)
          .where('from_uid', isEqualTo: _uid)
          .get();
      return snap.docs
          .where(
            (d) => List<String>.from(d.data()['types'] ?? []).contains(type),
          )
          .map((d) => d.data()['to_uid'] as String? ?? '')
          .where((u) => u.isNotEmpty)
          .toList();
    } catch (e) {
      return [];
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // PULL — recibir items compartidos desde Firebase → SQLite
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> pullSharedMenus() async {
    if (_uid.isEmpty) return;
    try {
      final snap = await _db
          .collection(_menusCol)
          .where('shared_with', arrayContains: _uid)
          .get();
      if (snap.docs.isEmpty) return;

      final rows = snap.docs.map((d) {
        final data = d.data();
        return {
          'id': d.id,
          'date': (data['date'] as Timestamp?)?.millisecondsSinceEpoch ?? 0,
          'meal_type': data['meal_type'] ?? 'Comida',
          'title': data['title'] ?? '',
          'description': data['description'] ?? '',
          'owner_id': data['owner_id'] ?? '',
          'owner_name': data['owner_name'] ?? '',
          'shared_with': _listToJson(data['shared_with']),
          'synced': 1,
        };
      }).toList();

      await DBProvider.db.batchInsert(DBSchema.tableWeeklyMenus, rows);
      debugPrint('📥 ${rows.length} menús compartidos recibidos');
    } catch (e) {
      debugPrint('❌ Error pullSharedMenus: $e');
    }
  }

  Future<void> pullSharedTasks() async {
    if (_uid.isEmpty) return;
    try {
      final snap = await _db
          .collection(_tasksCol)
          .where('shared_with', arrayContains: _uid)
          .get();
      if (snap.docs.isEmpty) return;

      final rows = snap.docs.map((d) {
        final data = d.data();
        return {
          'id': d.id,
          'date': (data['date'] as Timestamp?)?.millisecondsSinceEpoch ?? 0,
          'title': data['title'] ?? '',
          'description': data['description'] ?? '',
          'is_done': (data['is_done'] ?? false) ? 1 : 0,
          'owner_id': data['owner_id'] ?? '',
          'owner_name': data['owner_name'] ?? '',
          'shared_with': _listToJson(data['shared_with']),
          'recurrence': data['recurrence'] ?? 'none',
          'parent_id': data['parent_id'] ?? '',
          'synced': 1,
        };
      }).toList();

      await DBProvider.db.batchInsert(DBSchema.tableWeeklyTasks, rows);
      debugPrint('📥 ${rows.length} tareas compartidas recibidas');
    } catch (e) {
      debugPrint('❌ Error pullSharedTasks: $e');
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // LISTENERS — tiempo real para items compartidos conmigo
  // ══════════════════════════════════════════════════════════════════════════
  void startListening({VoidCallback? onChanged}) {
    stopListening();

    // ── Menús compartidos CONMIGO ─────────────────────────────────────────────
    final subMenus = _db
        .collection(_menusCol)
        .where('shared_with', arrayContains: _uid)
        .snapshots()
        .listen((snap) async {
          bool changed = false;
          for (final change in snap.docChanges) {
            final data = change.doc.data();
            if (data == null) continue;
            switch (change.type) {
              case DocumentChangeType.added:
              case DocumentChangeType.modified:
                await DBProvider.db.insertOrReplace(DBSchema.tableWeeklyMenus, {
                  'id': change.doc.id,
                  'date':
                      (data['date'] as Timestamp?)?.millisecondsSinceEpoch ?? 0,
                  'meal_type': data['meal_type'] ?? 'Comida',
                  'title': data['title'] ?? '',
                  'description': data['description'] ?? '',
                  'owner_id': data['owner_id'] ?? '',
                  'owner_name': data['owner_name'] ?? '',
                  'shared_with': _listToJson(data['shared_with']),
                  'synced': 1,
                });
                changed = true;
                break;
              case DocumentChangeType.removed:
                await DBProvider.db.delete(
                  DBSchema.tableWeeklyMenus,
                  where: 'id = ?',
                  whereArgs: [change.doc.id],
                );
                changed = true;
                break;
            }
          }
          if (changed) onChanged?.call();
        }, onError: (e) => debugPrint('❌ Listener weekly_menus: $e'));

    // ── Menús PROPIOS (para reflejar shared_with actualizado en local) ────────
    final subOwnMenus = _db
        .collection(_menusCol)
        .where('owner_id', isEqualTo: _uid)
        .snapshots()
        .listen((snap) async {
          bool changed = false;
          for (final change in snap.docChanges) {
            final data = change.doc.data();
            if (data == null) continue;
            switch (change.type) {
              case DocumentChangeType.added:
              case DocumentChangeType.modified:
                await DBProvider.db.insertOrReplace(DBSchema.tableWeeklyMenus, {
                  'id': change.doc.id,
                  'date':
                      (data['date'] as Timestamp?)?.millisecondsSinceEpoch ?? 0,
                  'meal_type': data['meal_type'] ?? 'Comida',
                  'title': data['title'] ?? '',
                  'description': data['description'] ?? '',
                  'owner_id': data['owner_id'] ?? _uid,
                  'owner_name': data['owner_name'] ?? '',
                  'shared_with': _listToJson(data['shared_with']),
                  'synced': 1,
                });
                changed = true;
                break;
              case DocumentChangeType.removed:
                await DBProvider.db.delete(
                  DBSchema.tableWeeklyMenus,
                  where: 'id = ?',
                  whereArgs: [change.doc.id],
                );
                changed = true;
                break;
            }
          }
          if (changed) onChanged?.call();
        }, onError: (e) => debugPrint('❌ Listener own weekly_menus: $e'));

    // ── Tareas compartidas CONMIGO (yo soy el destinatario) ───────────────────
    final subTasks = _db
        .collection(_tasksCol)
        .where('shared_with', arrayContains: _uid)
        .snapshots()
        .listen((snap) async {
          bool changed = false;
          for (final change in snap.docChanges) {
            final data = change.doc.data();
            if (data == null) continue;
            switch (change.type) {
              case DocumentChangeType.added:
              case DocumentChangeType.modified:
                await DBProvider.db.insertOrReplace(DBSchema.tableWeeklyTasks, {
                  'id': change.doc.id,
                  'date':
                      (data['date'] as Timestamp?)?.millisecondsSinceEpoch ?? 0,
                  'title': data['title'] ?? '',
                  'description': data['description'] ?? '',
                  'is_done': (data['is_done'] ?? false) ? 1 : 0,
                  'owner_id': data['owner_id'] ?? '',
                  'owner_name': data['owner_name'] ?? '',
                  'shared_with': _listToJson(data['shared_with']),
                  'recurrence': data['recurrence'] ?? 'none',
                  'parent_id': data['parent_id'] ?? '',
                  'synced': 1,
                });
                changed = true;
                break;
              case DocumentChangeType.removed:
                await DBProvider.db.delete(
                  DBSchema.tableWeeklyTasks,
                  where: 'id = ?',
                  whereArgs: [change.doc.id],
                );
                changed = true;
                break;
            }
          }
          if (changed) onChanged?.call();
        }, onError: (e) => debugPrint('❌ Listener weekly_tasks: $e'));

    // ── Tareas PROPIAS (yo soy el dueño) ──────────────────────────────────────
    final subOwnTasks = _db
        .collection(_tasksCol)
        .where('owner_id', isEqualTo: _uid)
        .snapshots()
        .listen((snap) async {
          bool changed = false;
          for (final change in snap.docChanges) {
            final data = change.doc.data();
            if (data == null) continue;
            switch (change.type) {
              case DocumentChangeType.added:
              case DocumentChangeType.modified:
                await DBProvider.db.insertOrReplace(DBSchema.tableWeeklyTasks, {
                  'id': change.doc.id,
                  'date':
                      (data['date'] as Timestamp?)?.millisecondsSinceEpoch ?? 0,
                  'title': data['title'] ?? '',
                  'description': data['description'] ?? '',
                  'is_done': (data['is_done'] ?? false) ? 1 : 0,
                  'owner_id': data['owner_id'] ?? _uid,
                  'owner_name': data['owner_name'] ?? '',
                  'shared_with': _listToJson(data['shared_with']),
                  'recurrence': data['recurrence'] ?? 'none',
                  'parent_id': data['parent_id'] ?? '',
                  'synced': 1,
                });
                changed = true;
                break;
              case DocumentChangeType.removed:
                await DBProvider.db.delete(
                  DBSchema.tableWeeklyTasks,
                  where: 'id = ?',
                  whereArgs: [change.doc.id],
                );
                changed = true;
                break;
            }
          }
          if (changed) onChanged?.call();
        }, onError: (e) => debugPrint('❌ Listener own weekly_tasks: $e'));

    _subscriptions.addAll([subMenus, subOwnMenus, subTasks, subOwnTasks]);
    debugPrint('👂 WeeklyShare listeners activos');
  }

  void stopListening() {
    for (final s in _subscriptions) s.cancel();
    _subscriptions.clear();
  }

  // ══════════════════════════════════════════════════════════════════════════
  // PRIVADOS
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> _addSharedWithToExisting(
    String collection,
    List<String> friendUids,
  ) async {
    try {
      final snap = await _db
          .collection(collection)
          .where('owner_id', isEqualTo: _uid)
          .get();
      if (snap.docs.isEmpty) return;

      final batch = _db.batch();
      for (final doc in snap.docs) {
        batch.update(doc.reference, {
          'shared_with': FieldValue.arrayUnion(friendUids),
          'updated_at': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
      debugPrint(
        '📤 ${snap.docs.length} docs de $collection actualizados con shared_with',
      );
    } catch (e) {
      debugPrint('❌ Error _addSharedWithToExisting $collection: $e');
    }
  }

  Future<void> _removeSharedWithFromExisting(
    String collection,
    List<String> friendUids,
  ) async {
    try {
      final snap = await _db
          .collection(collection)
          .where('owner_id', isEqualTo: _uid)
          .get();
      if (snap.docs.isEmpty) return;

      final batch = _db.batch();
      for (final doc in snap.docs) {
        batch.update(doc.reference, {
          'shared_with': FieldValue.arrayRemove(friendUids),
          'updated_at': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
    } catch (e) {
      debugPrint('❌ Error _removeSharedWithFromExisting $collection: $e');
    }
  }

  /// Convierte una lista dinámica de Firestore a JSON string para SQLite.
  String _listToJson(dynamic raw) {
    if (raw == null) return '';
    final list = raw as List<dynamic>;
    if (list.isEmpty) return '';
    return '[${list.map((e) => '"$e"').join(',')}]';
  }

  // ── Utilidades públicas de parseo de shared_with (usadas por los repos) ─────

  /// Parsea un shared_with local ('["a","b"]') a un Set<String>.
  static Set<String> parseUids(String json) {
    if (json.isEmpty) return <String>{};
    final matches = RegExp(r'"([^"]+)"').allMatches(json);
    return matches.map((m) => m.group(1)!).toSet();
  }

  /// Serializa un conjunto de UIDs al formato local JSON.
  static String uidsToJson(Iterable<String> uids) {
    final list = uids.where((u) => u.isNotEmpty).toSet().toList();
    if (list.isEmpty) return '';
    return '[${list.map((u) => '"$u"').join(',')}]';
  }
}
