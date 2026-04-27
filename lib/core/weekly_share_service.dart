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

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../models/friend_model.dart';
import '../models/weekly_menu_model.dart';
import '../models/weekly_task_model.dart';
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

  // ══════════════════════════════════════════════════════════════════════════
  // COMPARTIR
  // ══════════════════════════════════════════════════════════════════════════

  /// Comparte los tipos indicados (menus y/o tareas) con los amigos indicados.
  /// [types] puede contener 'menus', 'tasks' o ambos.
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

    // 1. Guardar configuración de compartir
    for (final fUid in friendUids) {
      await _db.collection(_sharesCol).doc('${_uid}_$fUid').set({
        'from_uid': _uid,
        'to_uid': fUid,
        'types': types,
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    // 2. Actualizar documentos existentes en Firebase
    if (types.contains('menus')) {
      await _addSharedWithToExisting(_menusCol, friendUids);
    }
    if (types.contains('tasks')) {
      await _addSharedWithToExisting(_tasksCol, friendUids);
    }

    debugPrint('📤 Weekly share: tipos=$types con ${friendUids.length} amigos');
  }

  /// Deja de compartir con los amigos indicados (quita su UID de todos los docs).
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
      // Actualizar o eliminar la configuración de compartir
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

    // Quitar shared_with de los documentos existentes
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
  // CONSULTA DE CONFIGURACIÓN ACTUAL
  // ══════════════════════════════════════════════════════════════════════════

  /// Obtiene la configuración de compartir actual del usuario.
  /// Devuelve una lista de { 'friend': FriendModel, 'types': List<String> }
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

  /// Lista de UIDs de amigos con los que comparto un tipo concreto.
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

    _subscriptions.addAll([subMenus, subTasks]);
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
}
