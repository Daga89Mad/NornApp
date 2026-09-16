// lib/core/date_change_service.dart
//
// Propuestas de cambio de fecha para items COMPARTIDOS.
//
// Flujo:
//   1. B mueve de día una tarea/menú/entrenamiento cuyo dueño es A.
//   2. A B se le aplica el cambio YA (override local, ver SharedDateOverrideService).
//   3. Se crea UN documento en 'date_change_requests' POR CADA destinatario
//      (dueño + resto de gente con la que está compartido, menos B), cada uno
//      con su 'to_uid'.
//   4. Cada uno, al abrir la pantalla correspondiente, ve un diálogo
//      "X propone mover ... del día A al día B" y decide.
//        · Acepta y es el DUEÑO  → cambia la fecha real del documento, con lo
//          que el cambio se propaga a todo el mundo.
//        · Acepta y NO es dueño  → se guarda su propio override local.
//        · Rechaza               → no pasa nada, el item sigue en su día.
//   5. Responder borra el documento propio.
//
// POR QUÉ UN DOC POR DESTINATARIO Y NO UN ARRAY:
//   Las reglas de Firestore no son filtros. En una consulta (list) no evalúan
//   documento a documento: intentan demostrar la regla a partir de los filtros
//   de la consulta. Una regla tipo 'uid in resource.data.audience' no se puede
//   demostrar desde un 'where(pending, arrayContains: uid)', así que Firestore
//   deniega la consulta ENTERA (permission-denied en el listener) aunque los
//   datos sean correctos. Con 'to_uid' y una igualdad sí se puede demostrar.
//
// Reglas de Firestore necesarias (colección 'date_change_requests'):
//   allow read:   request.auth.uid == resource.data.to_uid
//                 || request.auth.uid == resource.data.from_uid;
//   allow create: request.auth.uid == request.resource.data.from_uid;
//   allow delete: request.auth.uid == resource.data.to_uid
//                 || request.auth.uid == resource.data.from_uid;

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'db_provider.dart';
import 'db_schema.dart';
import 'shared_date_override_service.dart';

/// Una propuesta pendiente de responder por MÍ.
class PendingDateChange {
  final String id; // id del documento en Firestore
  final String itemId;
  final String itemType; // 'tasks' | 'menus' | 'trainings'
  final String itemTitle;
  final String ownerId;
  final String fromUid;
  final String fromName;
  final int oldDate;
  final int newDate;
  final int createdAt;

  const PendingDateChange({
    required this.id,
    required this.itemId,
    required this.itemType,
    required this.itemTitle,
    required this.ownerId,
    required this.fromUid,
    required this.fromName,
    required this.oldDate,
    required this.newDate,
    this.createdAt = 0,
  });

  factory PendingDateChange.fromMap(Map<String, dynamic> m) =>
      PendingDateChange(
        id: m['id'] as String,
        itemId: (m['item_id'] as String?) ?? '',
        itemType: (m['item_type'] as String?) ?? 'tasks',
        itemTitle: (m['item_title'] as String?) ?? '',
        ownerId: (m['owner_id'] as String?) ?? '',
        fromUid: (m['from_uid'] as String?) ?? '',
        fromName: (m['from_name'] as String?) ?? '',
        oldDate: (m['old_date'] as int?) ?? 0,
        newDate: (m['new_date'] as int?) ?? 0,
        createdAt: (m['created_at'] as int?) ?? 0,
      );

  Map<String, dynamic> toMap() => {
    'id': id,
    'item_id': itemId,
    'item_type': itemType,
    'item_title': itemTitle,
    'owner_id': ownerId,
    'from_uid': fromUid,
    'from_name': fromName,
    'old_date': oldDate,
    'new_date': newDate,
    'created_at': createdAt,
  };

  DateTime get oldDay => DateTime.fromMillisecondsSinceEpoch(oldDate);
  DateTime get newDay => DateTime.fromMillisecondsSinceEpoch(newDate);

  String get whoLabel => fromName.isNotEmpty ? fromName : 'Otra persona';

  String get typeLabel {
    switch (itemType) {
      case 'menus':
        return 'el menú';
      case 'trainings':
        return 'el entrenamiento';
      default:
        return 'la tarea';
    }
  }
}

class DateChangeService {
  DateChangeService._();
  static final DateChangeService instance = DateChangeService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  static const String _col = 'date_change_requests';

  final List<StreamSubscription> _subscriptions = [];

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';
  String get _displayName =>
      FirebaseAuth.instance.currentUser?.displayName ??
      FirebaseAuth.instance.currentUser?.email ??
      '';

  String _collectionFor(String type) {
    switch (type) {
      case 'menus':
        return 'weekly_menus';
      case 'trainings':
        return 'weekly_trainings';
      default:
        return 'weekly_tasks';
    }
  }

  String _tableFor(String type) {
    switch (type) {
      case 'menus':
        return DBSchema.tableWeeklyMenus;
      case 'trainings':
        return DBSchema.tableWeeklyTrainings;
      default:
        return DBSchema.tableWeeklyTasks;
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // CREAR PROPUESTA
  // ══════════════════════════════════════════════════════════════════════════

  /// Avisa al dueño y al resto de destinatarios de que he movido el item de día.
  ///
  /// [audience] debe ser: ownerId + todos los uids de shared_with, MENOS yo.
  /// Si queda vacía no se crea nada (no hay a quién preguntar).
  Future<void> propose({
    required String itemId,
    required String itemType,
    required String itemTitle,
    required String ownerId,
    required int oldDateMs,
    required int newDateMs,
    required Iterable<String> audience,
  }) async {
    final me = _uid;
    if (me.isEmpty || itemId.isEmpty) return;
    if (oldDateMs == newDateMs) return;

    final targets = audience
        .where((u) => u.isNotEmpty && u != me)
        .toSet()
        .toList();
    if (targets.isEmpty) {
      debugPrint(
        '⚠️ Propuesta NO enviada: audiencia vacía. '
        'Recibido=$audience yo=$me dueño=$ownerId item=$itemId',
      );
      return;
    }

    try {
      // Si ya había una propuesta viva para este item, la sustituimos.
      await _cancelExistingFor(itemId, itemType);

      // IMPORTANTE: un documento POR DESTINATARIO, con 'to_uid' como string.
      //
      // Las reglas de Firestore no son filtros: en una consulta (list) no miran
      // los documentos, intentan demostrar la regla a partir de los filtros de
      // la consulta. Con un array ('pending' arrayContains uid) no pueden
      // demostrar nada y deniegan la consulta entera. Con una igualdad
      // (to_uid == uid) sí, y por eso el destinatario puede leer lo suyo.
      final batch = _db.batch();
      for (final uid in targets) {
        batch.set(_db.collection(_col).doc(), {
          'item_id': itemId,
          'item_type': itemType,
          'item_title': itemTitle,
          'owner_id': ownerId,
          'from_uid': me,
          'from_name': _displayName,
          'to_uid': uid,
          'old_date': Timestamp.fromMillisecondsSinceEpoch(oldDateMs),
          'new_date': Timestamp.fromMillisecondsSinceEpoch(newDateMs),
          'created_at': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();

      debugPrint(
        '📤 Propuesta de fecha creada | item=$itemId tipo=$itemType '
        'yo=$me dueño=$ownerId destinatarios=$targets',
      );
    } catch (e) {
      debugPrint('❌ Error creando propuesta de fecha: $e');
    }
  }

  Future<void> _cancelExistingFor(String itemId, String itemType) async {
    try {
      final snap = await _db
          .collection(_col)
          .where('item_id', isEqualTo: itemId)
          .where('from_uid', isEqualTo: _uid)
          .get();
      for (final d in snap.docs) {
        if ((d.data()['item_type'] as String?) == itemType) {
          await d.reference.delete();
        }
      }
    } catch (e) {
      debugPrint('⚠️ No se pudo limpiar propuesta anterior: $e');
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // RECIBIR PROPUESTAS
  // ══════════════════════════════════════════════════════════════════════════

  /// Descarga a SQLite las propuestas en las que estoy pendiente.
  Future<void> pullPending() async {
    if (_uid.isEmpty) return;
    try {
      final snap = await _db
          .collection(_col)
          .where('to_uid', isEqualTo: _uid)
          .get();

      // Reemplazamos el espejo local por lo que diga el servidor.
      await DBProvider.db.delete(
        DBSchema.tablePendingDateChanges,
        where: '1 = 1',
        whereArgs: const [],
      );
      if (snap.docs.isEmpty) return;

      final rows = snap.docs.map((d) => _rowFromDoc(d.id, d.data())).toList();
      await DBProvider.db.batchInsert(DBSchema.tablePendingDateChanges, rows);
      debugPrint(
        '📥 ${rows.length} propuestas de fecha pendientes para uid=$_uid',
      );
    } catch (e) {
      debugPrint('❌ Error pullPending date changes: $e');
    }
  }

  Map<String, dynamic> _rowFromDoc(String id, Map<String, dynamic> data) => {
    'id': id,
    'item_id': data['item_id'] ?? '',
    'item_type': data['item_type'] ?? 'tasks',
    'item_title': data['item_title'] ?? '',
    'owner_id': data['owner_id'] ?? '',
    'from_uid': data['from_uid'] ?? '',
    'from_name': data['from_name'] ?? '',
    'old_date': (data['old_date'] as Timestamp?)?.millisecondsSinceEpoch ?? 0,
    'new_date': (data['new_date'] as Timestamp?)?.millisecondsSinceEpoch ?? 0,
    'created_at':
        (data['created_at'] as Timestamp?)?.millisecondsSinceEpoch ?? 0,
  };

  void startListening({VoidCallback? onChanged}) {
    stopListening();
    if (_uid.isEmpty) return;

    final sub = _db
        .collection(_col)
        .where('to_uid', isEqualTo: _uid)
        .snapshots()
        .listen((snap) async {
          bool changed = false;
          for (final change in snap.docChanges) {
            final data = change.doc.data();
            switch (change.type) {
              case DocumentChangeType.added:
              case DocumentChangeType.modified:
                if (data == null) continue;
                await DBProvider.db.insertOrReplace(
                  DBSchema.tablePendingDateChanges,
                  _rowFromDoc(change.doc.id, data),
                );
                changed = true;
                break;
              case DocumentChangeType.removed:
                await DBProvider.db.delete(
                  DBSchema.tablePendingDateChanges,
                  where: 'id = ?',
                  whereArgs: [change.doc.id],
                );
                changed = true;
                break;
            }
          }
          debugPrint(
            '📬 Propuestas de fecha para mí: ${snap.docs.length} '
            '(uid=$_uid)',
          );
          if (changed) onChanged?.call();
        }, onError: (e) => debugPrint('❌ Listener date_change_requests: $e'));

    _subscriptions.add(sub);
    debugPrint('👂 Listener de propuestas de fecha activo');
  }

  void stopListening() {
    for (final s in _subscriptions) {
      s.cancel();
    }
    _subscriptions.clear();
  }

  /// Propuestas pendientes de un tipo, para mostrarlas al entrar en la pantalla.
  Future<List<PendingDateChange>> pendingForType(String type) async {
    final rows = await DBProvider.db.query(
      DBSchema.tablePendingDateChanges,
      where: 'item_type = ?',
      whereArgs: [type],
      orderBy: 'created_at ASC',
    );
    return rows.map(PendingDateChange.fromMap).toList();
  }

  Future<int> pendingCount(String type) async =>
      (await pendingForType(type)).length;

  /// Todas las propuestas pendientes, sin filtrar por tipo.
  Future<List<PendingDateChange>> pendingAll() async {
    final rows = await DBProvider.db.query(
      DBSchema.tablePendingDateChanges,
      orderBy: 'created_at ASC',
    );
    return rows.map(PendingDateChange.fromMap).toList();
  }

  // ══════════════════════════════════════════════════════════════════════════
  // RESPONDER
  // ══════════════════════════════════════════════════════════════════════════

  /// Acepto el cambio.
  ///
  /// · Si soy el DUEÑO del item → cambio la fecha real (Firestore + local), con
  ///   lo que el movimiento se propaga a todos los que lo tengan compartido.
  /// · Si solo soy destinatario → me guardo un override local.
  Future<void> accept(PendingDateChange c) async {
    final me = _uid;
    if (me.isEmpty) return;

    try {
      if (c.ownerId == me) {
        await _applyRealDate(c);
      } else {
        await SharedDateOverrideService.instance.setOverride(
          c.itemId,
          c.itemType,
          c.newDate,
        );
        if (c.itemType == 'tasks') {
          await _overrideSubtasks(c.itemId, c.newDate);
        }
      }
    } catch (e) {
      debugPrint('❌ Error aplicando cambio de fecha aceptado: $e');
    }

    await _answer(c, accepted: true);
  }

  /// Rechazo el cambio: el item se queda donde estaba para mí.
  Future<void> reject(PendingDateChange c) async {
    await _answer(c, accepted: false);
  }

  /// Cambia la fecha REAL del documento (solo lo hace el dueño).
  Future<void> _applyRealDate(PendingDateChange c) async {
    final table = _tableFor(c.itemType);

    // Local
    final rows = await DBProvider.db.query(
      table,
      where: 'id = ?',
      whereArgs: [c.itemId],
      limit: '1',
    );
    if (rows.isNotEmpty) {
      final updated = Map<String, dynamic>.from(rows.first)
        ..['date'] = c.newDate
        ..['synced'] = 0;
      await DBProvider.db.insertOrReplace(table, updated);
    }

    // Firestore → se propaga al resto por los listeners ya existentes
    await _db.collection(_collectionFor(c.itemType)).doc(c.itemId).set({
      'date': Timestamp.fromMillisecondsSinceEpoch(c.newDate),
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // Las subtareas siguen a su tarea padre
    if (c.itemType == 'tasks') {
      final subs = await DBProvider.db.query(
        DBSchema.tableWeeklyTasks,
        where: 'parent_id = ?',
        whereArgs: [c.itemId],
      );
      for (final s in subs) {
        final sid = s['id'] as String;
        final updated = Map<String, dynamic>.from(s)
          ..['date'] = c.newDate
          ..['synced'] = 0;
        await DBProvider.db.insertOrReplace(DBSchema.tableWeeklyTasks, updated);
        await _db.collection('weekly_tasks').doc(sid).set({
          'date': Timestamp.fromMillisecondsSinceEpoch(c.newDate),
          'updated_at': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    }

    // Ya manda la fecha real: el override local sobra.
    await SharedDateOverrideService.instance.clear(c.itemId, c.itemType);
  }

  Future<void> _overrideSubtasks(String parentId, int newDate) async {
    final subs = await DBProvider.db.query(
      DBSchema.tableWeeklyTasks,
      where: 'parent_id = ?',
      whereArgs: [parentId],
    );
    for (final s in subs) {
      await SharedDateOverrideService.instance.setOverride(
        s['id'] as String,
        'tasks',
        newDate,
      );
    }
  }

  /// Como cada destinatario tiene su propio documento, responder es
  /// simplemente borrarlo: ya no está pendiente para nadie más.
  Future<void> _answer(PendingDateChange c, {required bool accepted}) async {
    // Fuera del espejo local pase lo que pase: ya he respondido.
    await DBProvider.db.delete(
      DBSchema.tablePendingDateChanges,
      where: 'id = ?',
      whereArgs: [c.id],
    );

    if (_uid.isEmpty) return;
    try {
      await _db.collection(_col).doc(c.id).delete();
      debugPrint(
        '✅ Propuesta ${accepted ? "aceptada" : "rechazada"} | doc=${c.id}',
      );
    } catch (e) {
      debugPrint('❌ Error respondiendo propuesta de fecha: $e');
    }
  }

  /// Descarta una propuesta local sin tocar Firestore (p. ej. si el item ya
  /// no existe para mí).
  Future<void> dropLocal(String id) async {
    await DBProvider.db.delete(
      DBSchema.tablePendingDateChanges,
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
