// lib/core/category_repository.dart
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../models/calendar_category.dart';
import 'db_provider.dart';
import 'db_schema.dart';

class CategoryRepository {
  CategoryRepository._();
  static final CategoryRepository instance = CategoryRepository._();

  final FirebaseFirestore _fs = FirebaseFirestore.instance;
  static const String _collection = 'calendar_categories';

  String? get _myUid => FirebaseAuth.instance.currentUser?.uid;

  String _generateKey() {
    final rand = Random();
    final suffix = List.generate(
      6,
      (_) => rand.nextInt(36).toRadixString(36),
    ).join();
    return 'cat_${DateTime.now().millisecondsSinceEpoch}_$suffix';
  }

  // ── Lectura ───────────────────────────────────────────────────────────────

  /// Integradas + personalizadas locales (propias e importadas de amigos).
  Future<List<CalendarCategory>> getAll() async {
    final custom = await getCustom();
    return [...CalendarCategory.builtIns(), ...custom];
  }

  Future<List<CalendarCategory>> getCustom() async {
    final rows = await DBProvider.db.getAll(DBSchema.tableCalendarCategories);
    return rows.map(CalendarCategory.fromMap).toList();
  }

  Future<CalendarCategory?> findByKey(String key) async {
    for (final c in CalendarCategory.builtIns()) {
      if (c.key == key) return c;
    }
    final rows = await DBProvider.db.query(
      DBSchema.tableCalendarCategories,
      where: 'id = ?',
      whereArgs: [key],
      limit: '1',
    );
    if (rows.isEmpty) return null;
    return CalendarCategory.fromMap(rows.first);
  }

  // ── Escritura local ─────────────────────────────────────────────────────────

  Future<CalendarCategory> create({
    required String label,
    required Color color,
    required String icon,
  }) async {
    final cat = CalendarCategory(
      key: _generateKey(),
      label: label.trim(),
      color: color,
      icon: icon,
      isBuiltIn: false,
      ownerId: _myUid,
      synced: false,
    );
    await DBProvider.db.insertOrReplace(
      DBSchema.tableCalendarCategories,
      cat.toMap(),
    );
    await _pushToFirestore(cat); // para poder compartirla después
    return cat;
  }

  Future<void> update(CalendarCategory cat) async {
    if (cat.isBuiltIn) return; // las integradas no se editan
    await DBProvider.db.insertOrReplace(
      DBSchema.tableCalendarCategories,
      cat.toMap(),
    );
    await _pushToFirestore(cat);
  }

  Future<void> delete(String key) async {
    await DBProvider.db.delete(
      DBSchema.tableCalendarCategories,
      where: 'id = ?',
      whereArgs: [key],
    );
  }

  // ── Firestore: propias ──────────────────────────────────────────────────────

  Future<void> _pushToFirestore(CalendarCategory cat) async {
    final uid = _myUid;
    if (uid == null) return;
    try {
      await _fs.collection(_collection).doc('${uid}_${cat.key}').set({
        ...cat.toFirestore(),
        'owner_id': uid,
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('❌ push categoría: $e');
    }
  }

  // ── Firestore: compartir ──────────────────────────────────────────────────

  /// Añade [friendUids] al shared_with de las categorías personalizadas
  /// indicadas, para que el amigo pueda importarlas.
  Future<void> shareCategories({
    required List<String> categoryKeys,
    required List<String> friendUids,
  }) async {
    final uid = _myUid;
    if (uid == null || friendUids.isEmpty) return;
    for (final key in categoryKeys) {
      try {
        await _fs.collection(_collection).doc('${uid}_$key').set({
          'shared_with': FieldValue.arrayUnion(friendUids),
          'updated_at': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (e) {
        debugPrint('❌ compartir categoría $key: $e');
      }
    }
  }

  /// Trae a la BD local las categorías que algún amigo ha compartido conmigo.
  /// Se guarda con la MISMA key para que cuadre con los eventos compartidos.
  /// Llamar al abrir el calendario (junto al resto de listeners).
  Future<int> importSharedCategories() async {
    final uid = _myUid;
    if (uid == null) return 0;
    int imported = 0;
    try {
      final snap = await _fs
          .collection(_collection)
          .where('shared_with', arrayContains: uid)
          .get();
      for (final doc in snap.docs) {
        final cat = CalendarCategory.fromFirestore(doc.data());
        await DBProvider.db.insertOrReplace(
          DBSchema.tableCalendarCategories,
          cat.copyWith(synced: true).toMap(),
        );
        imported++;
      }
    } catch (e) {
      debugPrint('❌ import categorías compartidas: $e');
    }
    return imported;
  }
}
