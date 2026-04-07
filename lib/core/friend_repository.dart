// lib/core/friend_repository.dart
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../models/friend_model.dart';
import 'db_provider.dart';
import 'db_schema.dart';
import 'firebase_sync_service.dart';

class FriendRepository {
  FriendRepository._();
  static final FriendRepository instance = FriendRepository._();

  String _generateId() {
    final rand = Random();
    final suffix = List.generate(
      8,
      (_) => rand.nextInt(36).toRadixString(36),
    ).join();
    return '${DateTime.now().millisecondsSinceEpoch}_$suffix';
  }

  Map<String, dynamic> _toMap(FriendModel f) => {
    'id': f.id ?? _generateId(),
    'name': f.name,
    'email': f.email,
    'alias': f.alias,
    'logo': f.logo,
    'firebase_uid': f.firebaseUid,
  };

  FriendModel _fromMap(Map<String, dynamic> m) => FriendModel(
    id: m['id'] as String?,
    name: m['name'] as String,
    email: m['email'] as String,
    alias: (m['alias'] as String?) ?? '',
    logo: (m['logo'] as String?) ?? '😊',
    firebaseUid: m['firebase_uid'] as String?,
  );

  Future<List<FriendModel>> getAll() async {
    final rows = await DBProvider.db.query(
      DBSchema.tableFriends,
      orderBy: 'name ASC',
    );
    return rows.map(_fromMap).toList();
  }

  Future<FriendModel> save(FriendModel friend) async {
    final id = friend.id ?? _generateId();
    final copy = FriendModel(
      id: id,
      name: friend.name,
      email: friend.email,
      alias: friend.alias,
      logo: friend.logo,
      firebaseUid: friend.firebaseUid,
    );
    // SQLite
    await DBProvider.db.insertOrReplace(DBSchema.tableFriends, _toMap(copy));
    // Firebase
    await FirebaseSyncService.instance.pushFriend(copy);
    return copy;
  }

  Future<void> delete(String id) async {
    // 1. Obtener el firebase_uid antes de borrar
    final rows = await DBProvider.db.query(
      DBSchema.tableFriends,
      where: 'id = ?',
      whereArgs: [id],
    );
    final friendUid = rows.isNotEmpty
        ? rows.first['firebase_uid'] as String?
        : null;

    // 2. Borrar localmente
    await DBProvider.db.delete(
      DBSchema.tableFriends,
      where: 'id = ?',
      whereArgs: [id],
    );

    // 3. Borrar en Firestore (mi copia del amigo)
    await FirebaseSyncService.instance.deleteFriend(id);

    // 4. Marcar la friend_request como 'removed' para que
    //    pullAcceptedRequests no vuelva a añadir este amigo.
    //    Solo buscamos la solicitud donde YO fui el emisor (from_uid).
    if (friendUid != null) {
      final myUid = FirebaseAuth.instance.currentUser?.uid;
      if (myUid != null) {
        try {
          final snap = await FirebaseFirestore.instance
              .collection('friend_requests')
              .where('from_uid', isEqualTo: myUid)
              .where('to_uid', isEqualTo: friendUid)
              .get();
          for (final doc in snap.docs) {
            await doc.reference.update({'status': 'removed'});
          }
          debugPrint('🗑️ Friend request marcada como removed');
        } catch (e) {
          debugPrint('⚠️ No se pudo marcar removed: \$e');
        }
      }
    }
  }

  /// Busca en Firestore user_profiles por email.
  Future<Map<String, String>?> lookupByEmail(String email) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('user_profiles')
          .where('email', isEqualTo: email.trim().toLowerCase())
          .limit(1)
          .get();
      if (snap.docs.isEmpty) return null;
      final data = snap.docs.first.data();
      return {
        'uid': snap.docs.first.id,
        'name': (data['name'] as String?) ?? email.split('@').first,
        'email': (data['email'] as String?) ?? email,
      };
    } catch (_) {
      return null;
    }
  }
}
