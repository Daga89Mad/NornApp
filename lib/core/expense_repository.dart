// lib/core/expense_repository.dart
//
// Acceso a Firestore del módulo de GASTOS. Ver el esquema en
// models/expense_models.dart.
//
// · Los gastos se escriben directamente en Firestore (su caché offline hace
//   que la app funcione sin red y se sincronice sola al recuperarla). Al ser
//   datos que editan VARIOS miembros a la vez, así no hay que mantener una
//   copia en SQLite ni resolver conflictos a mano.
// · Los totales del proyecto se actualizan con FieldValue.increment, que es
//   atómico aunque varios miembros añadan gastos a la vez.
// · generateDueInstances() crea los periodos pendientes de las series
//   periódicas. Se llama al entrar en la app (MenuScreen) y al abrir Gastos:
//   el primer miembro que entre lo crea, aunque sea días después del inicio.

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../models/expense_models.dart';
import '../models/friend_model.dart';
import 'week_dates.dart';

class ExpenseRepository {
  ExpenseRepository._();
  static final ExpenseRepository instance = ExpenseRepository._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  static const String _projectsCol = 'expense_projects';
  static const String _seriesCol = 'expense_series';
  static const String _expensesSub = 'expenses';

  /// Máximo de periodos que se crean de golpe por serie (p. ej. si nadie ha
  /// abierto la app en meses con una serie semanal).
  static const int _maxCatchUp = 60;

  String get uid => FirebaseAuth.instance.currentUser?.uid ?? '';
  String get myName =>
      FirebaseAuth.instance.currentUser?.displayName ??
      FirebaseAuth.instance.currentUser?.email ??
      'Yo';

  CollectionReference<Map<String, dynamic>> get _projects =>
      _db.collection(_projectsCol);
  CollectionReference<Map<String, dynamic>> get _series =>
      _db.collection(_seriesCol);
  CollectionReference<Map<String, dynamic>> _expenses(String projectId) =>
      _projects.doc(projectId).collection(_expensesSub);

  // ══════════════════════════════════════════════════════════════════════════
  // LECTURA (tiempo real)
  // ══════════════════════════════════════════════════════════════════════════

  /// Todos los proyectos en los que participo (propios y compartidos).
  /// Se ordenan en la pantalla, así no hace falta índice compuesto.
  Stream<List<ExpenseProject>> watchProjects() {
    if (uid.isEmpty) return Stream.value(const []);
    return _projects
        .where('members', arrayContains: uid)
        .snapshots()
        .map((s) => s.docs.map(ExpenseProject.fromDoc).toList());
  }

  Stream<ExpenseProject?> watchProject(String projectId) => _projects
      .doc(projectId)
      .snapshots()
      .map((d) => d.exists ? ExpenseProject.fromDoc(d) : null);

  Stream<ExpenseListSnapshot> watchExpenses(String projectId) =>
      _expenses(projectId)
          .snapshots(includeMetadataChanges: true)
          .map(
            (s) => ExpenseListSnapshot(
              s.docs.map(Expense.fromDoc).toList(),
              !s.metadata.isFromCache && !s.metadata.hasPendingWrites,
            ),
          );

  Future<ExpenseSeries?> getSeries(String seriesId) async {
    if (seriesId.isEmpty) return null;
    try {
      final d = await _series.doc(seriesId).get();
      return d.exists ? ExpenseSeries.fromDoc(d) : null;
    } catch (e) {
      debugPrint('❌ getSeries: $e');
      return null;
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // PROYECTOS
  // ══════════════════════════════════════════════════════════════════════════

  /// Crea un proyecto (y su serie si es periódico) con sus gastos iniciales.
  /// Devuelve el id del proyecto creado.
  Future<String> createProject({
    required String title,
    String description = '',
    required ExpenseProjectType type,
    int budgetCents = 0,
    required DateTime start,
    required DateTime end,
    required ExpenseRecurrence recurrence,
    required List<FriendModel> sharedWith,
    List<InitialExpense> initialExpenses = const [],
  }) async {
    if (uid.isEmpty) throw StateError('Sin sesión iniciada');

    final s = startOfDay(start);
    final e = startOfDay(end).isBefore(s) ? s : startOfDay(end);
    final (members, names) = _membersFrom(sharedWith);
    final batch = _db.batch();

    String seriesId = '';
    late final DocumentReference<Map<String, dynamic>> projectRef;

    if (recurrence.isRecurring) {
      final seriesRef = _series.doc();
      seriesId = seriesRef.id;
      final nextStart = occurrenceStart(s, recurrence, 1);
      final fullPeriod = isSameDay(e, addDays(nextStart, -1));
      batch.set(seriesRef, {
        'owner_id': uid,
        'owner_name': myName,
        'members': members,
        'member_names': names,
        'title': title,
        'description': description,
        'type': type.key,
        'budget_cents': type == ExpenseProjectType.subtract ? budgetCents : 0,
        'recurrence': recurrence.key,
        'anchor_start': Timestamp.fromDate(s),
        'duration_days': daysBetween(s, e),
        'full_period': fullPeriod,
        'next_index': 1,
        'active': true,
        'initial_expenses': initialExpenses.map((x) => x.toMap()).toList(),
        'created_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      });
      projectRef = _projects.doc('${seriesId}_0');
    } else {
      projectRef = _projects.doc();
    }

    _writeNewProject(
      ref: projectRef,
      seriesId: seriesId,
      index: 0,
      title: title,
      description: description,
      type: type,
      budgetCents: budgetCents,
      start: s,
      end: e,
      recurrence: recurrence,
      ownerId: uid,
      ownerName: myName,
      members: members,
      names: names,
      initialExpenses: initialExpenses,
      initialPayer: uid,
      createdBy: uid,
      write: (ref, data) => batch.set(ref, data),
    );

    await _commit(batch);
    return projectRef.id;
  }

  /// Edita un proyecto (solo el dueño). Si [applyToSeries] y el proyecto es
  /// periódico, los próximos periodos se crearán también con estos datos.
  Future<void> updateProject({
    required ExpenseProject project,
    required String title,
    String description = '',
    required ExpenseProjectType type,
    int budgetCents = 0,
    required DateTime start,
    required DateTime end,
    required List<FriendModel> sharedWith,
    bool applyToSeries = true,
  }) async {
    final s = startOfDay(start);
    final e = startOfDay(end).isBefore(s) ? s : startOfDay(end);
    final (newMembers, newNames) = _membersFrom(
      sharedWith,
      ownerId: project.ownerId,
      ownerName: project.ownerName,
    );
    // Se conservan los nombres de quien ya no está (aparece en gastos viejos).
    final names = <String, String>{...project.memberNames, ...newNames};

    final batch = _db.batch();
    batch.update(_projects.doc(project.id), {
      'title': title,
      'description': description,
      'type': type.key,
      'budget_cents': type == ExpenseProjectType.subtract ? budgetCents : 0,
      'start_date': Timestamp.fromDate(s),
      'end_date': Timestamp.fromDate(e),
      'members': newMembers,
      'member_names': names,
      'updated_at': FieldValue.serverTimestamp(),
    });

    if (applyToSeries && project.seriesId.isNotEmpty) {
      batch.update(_series.doc(project.seriesId), {
        'title': title,
        'description': description,
        'type': type.key,
        'budget_cents': type == ExpenseProjectType.subtract ? budgetCents : 0,
        'members': newMembers,
        'member_names': names,
        'updated_at': FieldValue.serverTimestamp(),
      });
    }
    await _commit(batch);
  }

  /// Deja de crear nuevos periodos (los ya creados se conservan).
  Future<void> stopSeries(String seriesId) async {
    if (seriesId.isEmpty) return;
    final batch = _db.batch();
    batch.update(_series.doc(seriesId), {
      'active': false,
      'updated_at': FieldValue.serverTimestamp(),
    });
    await _commit(batch);
  }

  /// Borra el proyecto y todos sus gastos (solo el dueño).
  Future<void> deleteProject(
    ExpenseProject project, {
    bool alsoStopSeries = false,
  }) async {
    final snap = await _expenses(project.id).get();
    final refs = snap.docs.map((d) => d.reference).toList();
    // Firestore admite 500 operaciones por batch.
    const chunk = 400;
    for (var i = 0; i < refs.length; i += chunk) {
      final batch = _db.batch();
      for (final r in refs.skip(i).take(chunk)) {
        batch.delete(r);
      }
      await _commit(batch);
    }
    final last = _db.batch();
    last.delete(_projects.doc(project.id));
    if (alsoStopSeries && project.seriesId.isNotEmpty) {
      last.update(_series.doc(project.seriesId), {
        'active': false,
        'updated_at': FieldValue.serverTimestamp(),
      });
    }
    await _commit(last);
  }

  /// Periodos (proyectos) que existen de la serie de [project], él incluido.
  /// Si no es periódico devuelve solo [project].
  Future<List<ExpenseProject>> seriesProjects(ExpenseProject project) async {
    if (project.seriesId.isEmpty) return [project];
    // Solo se filtra por 'members' (la misma consulta que la lista de
    // proyectos): combinarla con 'series_id' exigiría un índice compuesto.
    final snap = await _projects.where('members', arrayContains: uid).get();
    final list = snap.docs
        .map(ExpenseProject.fromDoc)
        .where((p) => p.seriesId == project.seriesId)
        .toList();
    if (!list.any((p) => p.id == project.id)) list.add(project);
    return list;
  }

  /// Borra TODOS los periodos de la serie de [project] (con sus gastos) y la
  /// propia serie, para que no se creen más. Solo el dueño.
  /// Devuelve cuántos periodos se han borrado.
  Future<int> deleteSeries(ExpenseProject project) async {
    if (project.seriesId.isEmpty) {
      await deleteProject(project);
      return 1;
    }
    // 1) Se detiene ANTES de buscar los periodos: así nadie crea uno nuevo
    //    mientras se borran. Si la serie ya no existe, no pasa nada.
    try {
      await stopSeries(project.seriesId);
    } catch (e) {
      debugPrint('⚠️ No se pudo detener la serie ${project.seriesId}: $e');
    }

    // 2) Todos los periodos, con sus gastos.
    final periods = await seriesProjects(project);
    for (final p in periods) {
      await deleteProject(p);
    }

    // 3) La propia serie. Si falla no es grave: ya está detenida.
    try {
      final batch = _db.batch();
      batch.delete(_series.doc(project.seriesId));
      await _commit(batch);
    } catch (e) {
      debugPrint('⚠️ No se pudo borrar la serie ${project.seriesId}: $e');
    }
    return periods.length;
  }

  /// Un miembro (no dueño) abandona el proyecto y sus próximos periodos.
  Future<void> leaveProject(ExpenseProject project) async {
    if (uid.isEmpty || project.isOwner(uid)) return;
    final batch = _db.batch();
    batch.update(_projects.doc(project.id), {
      'members': FieldValue.arrayRemove([uid]),
      'updated_at': FieldValue.serverTimestamp(),
    });
    if (project.seriesId.isNotEmpty) {
      batch.update(_series.doc(project.seriesId), {
        'members': FieldValue.arrayRemove([uid]),
        'updated_at': FieldValue.serverTimestamp(),
      });
    }
    await _commit(batch);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // GASTOS
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> addExpense({
    required ExpenseProject project,
    required String concept,
    required int amountCents,
    required DateTime date,
    required String paidByUid,
    String note = '',
  }) async {
    final batch = _db.batch();
    batch.set(_expenses(project.id).doc(), {
      'concept': concept,
      'amount_cents': amountCents,
      'date': Timestamp.fromDate(startOfDay(date)),
      'paid_by_uid': paidByUid,
      'paid_by_name': _nameIn(project, paidByUid),
      'created_by': uid,
      'note': note,
      'is_initial': false,
      'created_at': FieldValue.serverTimestamp(),
    });
    batch.update(_projects.doc(project.id), {
      'total_cents': FieldValue.increment(amountCents),
      'totals_by_uid.$paidByUid': FieldValue.increment(amountCents),
      'expense_count': FieldValue.increment(1),
      'updated_at': FieldValue.serverTimestamp(),
    });
    await _commit(batch);
  }

  Future<void> updateExpense({
    required ExpenseProject project,
    required Expense before,
    required Expense after,
  }) async {
    final batch = _db.batch();
    batch.update(_expenses(project.id).doc(before.id), {
      'concept': after.concept,
      'amount_cents': after.amountCents,
      'date': Timestamp.fromDate(startOfDay(after.date)),
      'paid_by_uid': after.paidByUid,
      'paid_by_name': _nameIn(project, after.paidByUid),
      'note': after.note,
      'updated_at': FieldValue.serverTimestamp(),
    });

    final delta = after.amountCents - before.amountCents;
    final updates = <String, dynamic>{
      'updated_at': FieldValue.serverTimestamp(),
    };
    if (delta != 0) updates['total_cents'] = FieldValue.increment(delta);
    if (before.paidByUid == after.paidByUid) {
      if (delta != 0) {
        updates['totals_by_uid.${after.paidByUid}'] = FieldValue.increment(
          delta,
        );
      }
    } else {
      updates['totals_by_uid.${before.paidByUid}'] = FieldValue.increment(
        -before.amountCents,
      );
      updates['totals_by_uid.${after.paidByUid}'] = FieldValue.increment(
        after.amountCents,
      );
    }
    batch.update(_projects.doc(project.id), updates);
    await _commit(batch);
  }

  Future<void> deleteExpense({
    required ExpenseProject project,
    required Expense expense,
  }) async {
    final batch = _db.batch();
    batch.delete(_expenses(project.id).doc(expense.id));
    batch.update(_projects.doc(project.id), {
      'total_cents': FieldValue.increment(-expense.amountCents),
      'totals_by_uid.${expense.paidByUid}': FieldValue.increment(
        -expense.amountCents,
      ),
      'expense_count': FieldValue.increment(-1),
      'updated_at': FieldValue.serverTimestamp(),
    });
    await _commit(batch);
  }

  /// Si los totales agregados del proyecto no cuadran con los gastos reales
  /// (p. ej. una escritura perdida), los corrige. Solo se llama con datos
  /// confirmados por el servidor.
  Future<void> reconcileTotals(
    ExpenseProject project,
    List<Expense> expenses,
  ) async {
    final byUid = <String, int>{};
    var total = 0;
    for (final e in expenses) {
      total += e.amountCents;
      byUid[e.paidByUid] = (byUid[e.paidByUid] ?? 0) + e.amountCents;
    }
    final storedByUid = Map<String, int>.from(project.totalsByUid)
      ..removeWhere((_, v) => v == 0);
    final same =
        total == project.totalCents &&
        expenses.length == project.expenseCount &&
        mapEquals(storedByUid, byUid);
    if (same) return;
    try {
      await _projects.doc(project.id).update({
        'total_cents': total,
        'totals_by_uid': byUid,
        'expense_count': expenses.length,
      });
      debugPrint('🧮 Totales de ${project.id} corregidos');
    } catch (e) {
      debugPrint('⚠️ reconcileTotals: $e');
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // PERIODOS AUTOMÁTICOS
  // ══════════════════════════════════════════════════════════════════════════

  bool _generating = false;

  /// Crea los periodos que ya deberían existir de todas mis series activas.
  /// Idempotente: el id del periodo es fijo ('{serie}_{n}') y se crea dentro
  /// de una transacción, así que aunque varios miembros entren a la vez solo
  /// se crea una vez. Devuelve cuántos periodos ha creado ESTE dispositivo.
  Future<int> generateDueInstances() async {
    if (uid.isEmpty || _generating) return 0;
    _generating = true;
    var created = 0;
    try {
      final snap = await _series.where('members', arrayContains: uid).get();
      final today = startOfDay(DateTime.now());

      for (final doc in snap.docs) {
        final s = ExpenseSeries.fromDoc(doc);
        if (!s.active || !s.recurrence.isRecurring) continue;
        try {
          var n = s.nextIndex;
          var guard = 0;
          while (guard++ < _maxCatchUp && !s.startOf(n).isAfter(today)) {
            if (await _createOccurrence(doc.reference, n)) created++;
            n++;
          }
        } catch (e) {
          debugPrint('⚠️ Serie ${s.id}: no se pudieron crear periodos: $e');
        }
      }
    } catch (e) {
      debugPrint('❌ generateDueInstances: $e');
    } finally {
      _generating = false;
    }
    if (created > 0) debugPrint('🗓️ $created periodos de gastos creados');
    return created;
  }

  Future<bool> _createOccurrence(
    DocumentReference<Map<String, dynamic>> seriesRef,
    int n,
  ) {
    return _db.runTransaction<bool>((tx) async {
      final sSnap = await tx.get(seriesRef);
      if (!sSnap.exists) return false;
      final s = ExpenseSeries.fromDoc(sSnap);
      if (!s.active) return false;

      final projectRef = _projects.doc('${s.id}_$n');
      final pSnap = await tx.get(projectRef);

      var createdNow = false;
      if (!pSnap.exists && s.nextIndex <= n) {
        _writeNewProject(
          ref: projectRef,
          seriesId: s.id,
          index: n,
          title: s.title,
          description: s.description,
          type: s.type,
          budgetCents: s.budgetCents,
          start: s.startOf(n),
          end: s.endOf(n),
          recurrence: s.recurrence,
          ownerId: s.ownerId,
          ownerName: s.ownerName,
          members: s.members,
          names: s.memberNames,
          initialExpenses: s.initialExpenses,
          initialPayer: s.ownerId,
          createdBy: s.ownerId,
          write: (ref, data) => tx.set(ref, data),
        );
        createdNow = true;
      }
      if (s.nextIndex <= n) {
        tx.update(seriesRef, {
          'next_index': n + 1,
          'updated_at': FieldValue.serverTimestamp(),
        });
      }
      return createdNow;
    });
  }

  // ══════════════════════════════════════════════════════════════════════════
  // PRIVADOS
  // ══════════════════════════════════════════════════════════════════════════

  /// Escribe el documento del proyecto y sus gastos iniciales con la función
  /// de escritura que se le pase (WriteBatch.set o Transaction.set).
  void _writeNewProject({
    required DocumentReference<Map<String, dynamic>> ref,
    required String seriesId,
    required int index,
    required String title,
    required String description,
    required ExpenseProjectType type,
    required int budgetCents,
    required DateTime start,
    required DateTime end,
    required ExpenseRecurrence recurrence,
    required String ownerId,
    required String ownerName,
    required List<String> members,
    required Map<String, String> names,
    required List<InitialExpense> initialExpenses,
    required String initialPayer,
    required String createdBy,
    required void Function(
      DocumentReference<Map<String, dynamic>> ref,
      Map<String, dynamic> data,
    )
    write,
  }) {
    final valid = initialExpenses
        .where((x) => x.concept.trim().isNotEmpty && x.amountCents > 0)
        .toList();
    final total = valid.fold<int>(0, (a, x) => a + x.amountCents);

    write(ref, {
      'series_id': seriesId,
      'occurrence_index': index,
      'title': title,
      'description': description,
      'type': type.key,
      'budget_cents': type == ExpenseProjectType.subtract ? budgetCents : 0,
      'start_date': Timestamp.fromDate(start),
      'end_date': Timestamp.fromDate(end),
      'recurrence': recurrence.key,
      'owner_id': ownerId,
      'owner_name': ownerName,
      'members': members,
      'member_names': names,
      'total_cents': total,
      'totals_by_uid': total > 0 ? {initialPayer: total} : <String, int>{},
      'expense_count': valid.length,
      'created_at': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
    });

    for (var i = 0; i < valid.length; i++) {
      write(ref.collection(_expensesSub).doc('init_$i'), {
        'concept': valid[i].concept.trim(),
        'amount_cents': valid[i].amountCents,
        'date': Timestamp.fromDate(start),
        'paid_by_uid': initialPayer,
        'paid_by_name': names[initialPayer] ?? ownerName,
        'created_by': createdBy,
        'note': '',
        'is_initial': true,
        'created_at': FieldValue.serverTimestamp(),
      });
    }
  }

  /// members (dueño primero) + nombres a partir de los amigos elegidos.
  (List<String>, Map<String, String>) _membersFrom(
    List<FriendModel> friends, {
    String? ownerId,
    String? ownerName,
  }) {
    final owner = ownerId ?? uid;
    final members = <String>[owner];
    final names = <String, String>{owner: ownerName ?? myName};
    for (final f in friends) {
      final fUid = f.firebaseUid;
      if (fUid == null || fUid.isEmpty || members.contains(fUid)) continue;
      members.add(fUid);
      names[fUid] = f.name.isNotEmpty ? f.name : f.email;
    }
    return (members, names);
  }

  String _nameIn(ExpenseProject p, String who) {
    if (who == uid) return myName;
    return p.memberNames[who] ?? '';
  }

  /// Con red, espera la confirmación del servidor (y propaga los errores de
  /// permisos). Sin red, Firestore deja el cambio en cola y el Future no
  /// termina hasta reconectar: tras unos segundos se da por encolado para no
  /// dejar la pantalla bloqueada.
  Future<void> _commit(WriteBatch batch) async {
    try {
      await batch.commit().timeout(const Duration(seconds: 6));
    } on TimeoutException {
      debugPrint('⏳ Sin conexión: el cambio se subirá al recuperar la red');
    }
  }
}
