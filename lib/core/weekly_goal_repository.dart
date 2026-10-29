// lib/core/weekly_goal_repository.dart
//
// Objetivos semanales (ver WeeklyGoal). Viven solo en Firestore, colección
// 'weekly_goals'; Firestore ya los cachea en el móvil para usarlos sin red.
//
// Compartir:
//   · Al crear un objetivo hereda el reparto global de esa pantalla
//     (Compartir → Menús / Tareas / Entrenamiento).
//   · Además se puede compartir o dejar de compartir cada objetivo suelto.
//   · Quien lo recibe puede marcarlo como conseguido (cambia para todos) y
//     "Quitarlo" solo de su semana (DismissedSharedService, tipo 'goals').

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/weekly_goal_model.dart';
import 'dismissed_shared_service.dart';
import 'week_dates.dart';
import 'weekly_share_service.dart';

class WeeklyGoalRepository {
  WeeklyGoalRepository._();
  static final WeeklyGoalRepository instance = WeeklyGoalRepository._();

  static const String _collection = 'weekly_goals';
  static const String dismissType = 'goals';

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';
  String get _displayName =>
      FirebaseAuth.instance.currentUser?.displayName ??
      FirebaseAuth.instance.currentUser?.email ??
      '';

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection(_collection);

  /// Avisa de cambios que solo existen en este móvil (quitar un objetivo
  /// compartido), que Firestore no notifica.
  final StreamController<void> _localChanges =
      StreamController<void>.broadcast();

  /// Objetivos de [type] para la semana de [anyDayOfWeek]: los míos y los que
  /// me han compartido (sin los que he quitado). Se actualiza en tiempo real.
  Stream<List<WeeklyGoal>> watchWeek(String type, DateTime anyDayOfWeek) {
    final uid = _uid;
    if (uid.isEmpty) return Stream.value(const []);
    final weekKey = WeeklyGoal.weekKeyOf(mondayOf(anyDayOfWeek));

    final ownQuery = _col
        .where('owner_id', isEqualTo: uid)
        .where('week_key', isEqualTo: weekKey);
    final sharedQuery = _col
        .where('shared_with', arrayContains: uid)
        .where('week_key', isEqualTo: weekKey);

    late StreamController<List<WeeklyGoal>> controller;
    StreamSubscription? subOwn;
    StreamSubscription? subShared;
    StreamSubscription? subLocal;
    List<WeeklyGoal> own = const [];
    List<WeeklyGoal> shared = const [];

    Future<void> emit() async {
      final dismissed = await DismissedSharedService.instance.idsForType(
        dismissType,
      );
      final all = <String, WeeklyGoal>{};
      for (final g in [...own, ...shared]) {
        if (g.type != type) continue;
        if (g.ownerId != uid && dismissed.contains(g.id)) continue;
        all[g.id] = g;
      }
      final list = all.values.toList()
        ..sort((a, b) {
          // Pendientes primero; después, por título.
          if (a.isDone != b.isDone) return a.isDone ? 1 : -1;
          return a.title.toLowerCase().compareTo(b.title.toLowerCase());
        });
      if (!controller.isClosed) controller.add(list);
    }

    controller = StreamController<List<WeeklyGoal>>(
      onListen: () {
        subOwn = ownQuery.snapshots().listen((snap) {
          own = snap.docs.map(WeeklyGoal.fromDoc).toList();
          emit();
        }, onError: (e) => debugPrint('❌ Objetivos propios: $e'));
        subShared = sharedQuery.snapshots().listen((snap) {
          shared = snap.docs.map(WeeklyGoal.fromDoc).toList();
          emit();
        }, onError: (e) => debugPrint('❌ Objetivos compartidos: $e'));
        subLocal = _localChanges.stream.listen((_) => emit());
      },
      onCancel: () async {
        await subOwn?.cancel();
        await subShared?.cancel();
        await subLocal?.cancel();
      },
    );
    return controller.stream;
  }

  /// Crea un objetivo en la semana de [anyDayOfWeek]. Hereda el reparto global
  /// de la pantalla [type].
  Future<void> create({
    required String type,
    required DateTime anyDayOfWeek,
    required String title,
  }) async {
    final t = title.trim();
    if (_uid.isEmpty || t.isEmpty) return;

    final shares = <String>{};
    try {
      shares.addAll(
        await WeeklyShareService.instance.getSharedUidsForType(type),
      );
    } catch (e) {
      debugPrint('⚠️ No se pudo leer el reparto global ($type): $e');
    }
    shares
      ..remove(_uid)
      ..remove('');

    final goal = WeeklyGoal(
      id: '',
      type: type,
      weekKey: WeeklyGoal.weekKeyOf(mondayOf(anyDayOfWeek)),
      title: t,
      ownerId: _uid,
      ownerName: _displayName,
      sharedWith: shares.toList(),
    );
    await _col.add(goal.toFirestore());
  }

  /// Cambia el título (solo el dueño).
  Future<void> rename(WeeklyGoal goal, String title) async {
    final t = title.trim();
    if (t.isEmpty || goal.isSharedFromOther(_uid)) return;
    await _col.doc(goal.id).update({
      'title': t,
      'updated_at': FieldValue.serverTimestamp(),
    });
  }

  /// Marca o desmarca como conseguido. Cambia para todos los que lo tengan.
  Future<void> toggleDone(WeeklyGoal goal) async {
    await _col.doc(goal.id).set({
      'is_done': !goal.isDone,
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Propio → se borra para todos.
  /// Compartido conmigo → solo se quita de mi semana.
  Future<void> delete(WeeklyGoal goal) async {
    if (goal.isSharedFromOther(_uid)) {
      await DismissedSharedService.instance.dismiss(goal.id, dismissType);
      _localChanges.add(null);
      return;
    }
    await _col.doc(goal.id).delete();
  }

  /// Deja el objetivo compartido exactamente con [uids] (solo el dueño).
  Future<void> setSharedWith(WeeklyGoal goal, Set<String> uids) async {
    if (goal.isSharedFromOther(_uid)) return;
    final clean = {...uids}
      ..remove(_uid)
      ..remove('');
    await _col.doc(goal.id).update({
      'shared_with': clean.toList(),
      'updated_at': FieldValue.serverTimestamp(),
    });
  }
}
