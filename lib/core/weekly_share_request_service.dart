// lib/core/weekly_share_request_service.dart
//
// Peticiones para COMPARTIR CON MÁS GENTE un elemento semanal (tarea, menú o
// entrenamiento) que OTRA persona ha compartido conmigo.
//
// Mismo flujo que en el calendario (EventChangeService → add_shared_with):
//   1. B tiene una tarea cuyo dueño es A y quiere compartirla con C (amigo de
//      B, aunque no lo sea de A). Solo el dueño puede cambiar 'shared_with'
//      (reglas de Firestore), así que se crea una petición en
//      'date_change_requests' con item_type = '<tipo>_share' y to_uid = A.
//   2. A recibe un push (Cloud Function notifyDateChange) y, al abrir la
//      pantalla semanal, ve "B quiere compartir «X» con C".
//        · Acepta  → A comparte la tarea (y sus subtareas) con C, igual que
//                    con "Compartir solo esta tarea".
//        · Rechaza → no pasa nada.
//   3. Responder borra la petición.
//
// Se reutiliza 'date_change_requests' (y sus reglas) para no necesitar reglas
// nuevas. DateChangeService ignora los docs cuyo item_type acaba en '_share'.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'weekly_share_service.dart';

/// Petición pendiente de compartir uno de mis elementos con más personas.
class WeeklyShareRequest {
  final String id;
  final String itemId;
  final String itemTitle;

  /// 'tasks' | 'menus' | 'trainings'
  final String type;
  final String fromUid;
  final String fromName;

  /// UIDs con los que quien lo pide quiere compartirlo.
  final List<String> addSharedWith;

  /// Nombres para mostrar de [addSharedWith] (pueden no ser amigos míos).
  final List<String> addSharedNames;

  const WeeklyShareRequest({
    required this.id,
    required this.itemId,
    required this.itemTitle,
    required this.type,
    required this.fromUid,
    required this.fromName,
    required this.addSharedWith,
    required this.addSharedNames,
  });

  String get whoLabel => fromName.isNotEmpty ? fromName : 'Otra persona';

  String get namesLabel {
    final names = addSharedNames.where((n) => n.trim().isNotEmpty).toList();
    if (names.isEmpty) {
      final n = addSharedWith.length;
      return n == 1 ? 'otra persona' : '$n personas';
    }
    if (names.length == 1) return names.first;
    return '${names.sublist(0, names.length - 1).join(', ')} y ${names.last}';
  }

  factory WeeklyShareRequest.fromDoc(String id, Map<String, dynamic> d) {
    final raw = (d['item_type'] as String?) ?? '';
    return WeeklyShareRequest(
      id: id,
      itemId: (d['item_id'] as String?) ?? '',
      itemTitle: (d['item_title'] as String?) ?? '',
      type: WeeklyShareRequestService.baseType(raw),
      fromUid: (d['from_uid'] as String?) ?? '',
      fromName: (d['from_name'] as String?) ?? '',
      addSharedWith: List<String>.from(d['add_shared_with'] ?? const []),
      addSharedNames: List<String>.from(d['add_shared_names'] ?? const []),
    );
  }
}

class WeeklyShareRequestService {
  WeeklyShareRequestService._();
  static final WeeklyShareRequestService instance =
      WeeklyShareRequestService._();

  static const String _col = 'date_change_requests';
  static const String suffix = '_share';

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';
  String get _displayName =>
      FirebaseAuth.instance.currentUser?.displayName ??
      FirebaseAuth.instance.currentUser?.email ??
      '';

  /// ¿Este item_type es una petición de compartir? ('tasks_share', …)
  static bool isShareType(Object? itemType) =>
      itemType is String && itemType.endsWith(suffix);

  /// 'tasks_share' → 'tasks'
  static String baseType(String itemType) => itemType.endsWith(suffix)
      ? itemType.substring(0, itemType.length - suffix.length)
      : itemType;

  // ══════════════════════════════════════════════════════════════════════════
  // PEDIR
  // ══════════════════════════════════════════════════════════════════════════

  /// Pide al dueño ([ownerId]) que comparta [itemId] también con [uids].
  /// Devuelve false si no hay nadie nuevo o si falla el envío.
  Future<bool> request({
    required String type, // 'tasks' | 'menus' | 'trainings'
    required String itemId,
    required String itemTitle,
    required String ownerId,
    required List<String> uids,
    required List<String> names,
    Set<String> alreadyShared = const {},
  }) async {
    final me = _uid;
    if (me.isEmpty || ownerId.isEmpty || ownerId == me || itemId.isEmpty) {
      return false;
    }

    // Solo gente que aún no la tiene.
    final add = <String>[];
    final addNames = <String>[];
    for (var i = 0; i < uids.length; i++) {
      final u = uids[i];
      if (u.isEmpty || u == me || u == ownerId) continue;
      if (alreadyShared.contains(u) || add.contains(u)) continue;
      add.add(u);
      addNames.add(i < names.length ? names[i] : '');
    }
    if (add.isEmpty) return false;

    final itemType = '$type$suffix';
    try {
      await _cancelMine(itemId, itemType);
      await _db.collection(_col).add({
        'item_id': itemId,
        'item_type': itemType,
        'item_title': itemTitle,
        'owner_id': ownerId,
        'from_uid': me,
        'from_name': _displayName,
        'to_uid': ownerId,
        'add_shared_with': add,
        'add_shared_names': addNames,
        'created_at': FieldValue.serverTimestamp(),
      });
      debugPrint('📤 Petición de compartir enviada | $itemType=$itemId '
          'dueño=$ownerId añadir=$add');
      return true;
    } catch (e) {
      debugPrint('❌ Error enviando petición de compartir: $e');
      return false;
    }
  }

  /// Si ya había pedido compartir este elemento, la petición se sustituye.
  Future<void> _cancelMine(String itemId, String itemType) async {
    try {
      final snap = await _db
          .collection(_col)
          .where('item_id', isEqualTo: itemId)
          .where('from_uid', isEqualTo: _uid)
          .get();
      for (final d in snap.docs) {
        if (d.data()['item_type'] == itemType) await d.reference.delete();
      }
    } catch (e) {
      debugPrint('⚠️ No se pudo limpiar la petición anterior: $e');
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // RECIBIR
  // ══════════════════════════════════════════════════════════════════════════

  /// Peticiones sobre mis elementos de [type] pendientes de responder.
  Future<List<WeeklyShareRequest>> pendingForMe(String type) async {
    if (_uid.isEmpty) return [];
    try {
      final snap = await _db
          .collection(_col)
          .where('to_uid', isEqualTo: _uid)
          .get();
      return snap.docs
          .where((d) => d.data()['item_type'] == '$type$suffix')
          .map((d) => WeeklyShareRequest.fromDoc(d.id, d.data()))
          .toList();
    } catch (e) {
      debugPrint('❌ Error leyendo peticiones de compartir: $e');
      return [];
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // RESPONDER
  // ══════════════════════════════════════════════════════════════════════════

  /// Acepto: comparto el elemento (y sus subtareas) con las personas pedidas.
  Future<bool> accept(WeeklyShareRequest r) async {
    try {
      for (final uid in r.addSharedWith) {
        await WeeklyShareService.instance.shareSingleItem(
          type: r.type,
          docId: r.itemId,
          friendUid: uid,
        );
      }
      await _delete(r.id);
      debugPrint('✅ Petición de compartir aceptada | ${r.itemId}');
      return true;
    } catch (e) {
      debugPrint('❌ Error aceptando petición de compartir: $e');
      return false;
    }
  }

  Future<void> reject(WeeklyShareRequest r) => _delete(r.id);

  Future<void> _delete(String id) async {
    try {
      await _db.collection(_col).doc(id).delete();
    } catch (e) {
      debugPrint('❌ Error borrando petición $id: $e');
    }
  }
}
