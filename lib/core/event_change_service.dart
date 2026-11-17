// lib/core/event_change_service.dart
//
// Propuestas de cambio sobre EVENTOS DEL CALENDARIO compartidos.
//
// Flujo (igual espíritu que las tareas semanales):
//   1. B edita un evento cuyo dueño es A. No se toca el evento: se crea una
//      propuesta en 'date_change_requests' con item_type = 'events',
//      to_uid = A y un mapa 'changes' con solo los campos que cambian.
//      B también puede pedir compartirlo con terceros ('add_shared_with'),
//      aunque esos terceros no sean amigos de A.
//   2. A recibe un push (Cloud Function notifyDateChange) y, al abrir el
//      calendario, ve "B propone cambios en «X»" con el detalle.
//        · Acepta  → A aplica los cambios a su evento (local + Firestore).
//                    El evento se propaga a todos por la sincronización normal
//                    y la Cloud Function onSharedEventWrite avisa al resto.
//        · Rechaza → no pasa nada.
//   3. Responder borra la propuesta.
//
// Se reutiliza la colección 'date_change_requests' (y sus reglas: lee to_uid
// o from_uid, crea from_uid, borra to_uid o from_uid) para no necesitar
// reglas nuevas. DateChangeService ignora los docs con item_type 'events'.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../models/event_item.dart';
import 'db_provider.dart';
import 'db_schema.dart';
import 'event_repository.dart';

/// Propuesta de cambios sobre un evento mío, pendiente de responder.
class EventChangeProposal {
  final String id;
  final String eventId;
  final String eventTitle;
  final String ownerId;
  final String fromUid;
  final String fromName;
  final DateTime oldDay;
  final DateTime newDay;

  /// Campos que cambian, con el mismo nombre que en Firestore
  /// (title, description, from_minutes, to_minutes, category, tipo, icon,
  /// color).
  final Map<String, dynamic> changes;

  /// UIDs con los que quien propone quiere compartirlo además.
  final List<String> addSharedWith;

  /// Nombres para mostrar de [addSharedWith] (pueden no ser amigos míos).
  final List<String> addSharedNames;

  const EventChangeProposal({
    required this.id,
    required this.eventId,
    required this.eventTitle,
    required this.ownerId,
    required this.fromUid,
    required this.fromName,
    required this.oldDay,
    required this.newDay,
    required this.changes,
    required this.addSharedWith,
    required this.addSharedNames,
  });

  bool get movesDay =>
      oldDay.year != newDay.year ||
      oldDay.month != newDay.month ||
      oldDay.day != newDay.day;

  String get whoLabel => fromName.isNotEmpty ? fromName : 'Otra persona';

  factory EventChangeProposal.fromDoc(String id, Map<String, dynamic> d) {
    DateTime day(Object? ts) {
      final dt = (ts as Timestamp?)?.toDate() ?? DateTime.now();
      return DateTime(dt.year, dt.month, dt.day);
    }

    return EventChangeProposal(
      id: id,
      eventId: (d['item_id'] as String?) ?? '',
      eventTitle: (d['item_title'] as String?) ?? '',
      ownerId: (d['owner_id'] as String?) ?? '',
      fromUid: (d['from_uid'] as String?) ?? '',
      fromName: (d['from_name'] as String?) ?? '',
      oldDay: day(d['old_date']),
      newDay: day(d['new_date']),
      changes: Map<String, dynamic>.from(d['changes'] as Map? ?? const {}),
      addSharedWith: List<String>.from(d['add_shared_with'] ?? const []),
      addSharedNames: List<String>.from(d['add_shared_names'] ?? const []),
    );
  }
}

class EventChangeService {
  EventChangeService._();
  static final EventChangeService instance = EventChangeService._();

  static const String itemType = 'events';
  static const String _col = 'date_change_requests';

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';
  String get _displayName =>
      FirebaseAuth.instance.currentUser?.displayName ??
      FirebaseAuth.instance.currentUser?.email ??
      '';

  /// ¿El evento es de otra persona (compartido conmigo)?
  bool isForeign(EventItem ev) {
    final owner = ev.ownerId;
    return owner != null && owner.isNotEmpty && owner != _uid;
  }

  static int _minutes(TimeOfDay t) => t.hour * 60 + t.minute;

  // ══════════════════════════════════════════════════════════════════════════
  // PROPONER
  // ══════════════════════════════════════════════════════════════════════════

  /// Envía al dueño de [original] una propuesta con lo que cambia en [edited].
  ///
  /// Devuelve false si no hay nada que proponer o si falla el envío.
  Future<bool> propose({
    required EventItem original,
    required DateTime originalDay,
    required EventItem edited,
    required DateTime newDay,
    List<String> addSharedWith = const [],
    List<String> addSharedNames = const [],
  }) async {
    final me = _uid;
    final owner = original.ownerId ?? '';
    final eventId = original.id ?? '';
    if (me.isEmpty || owner.isEmpty || owner == me || eventId.isEmpty) {
      return false;
    }

    final changes = <String, dynamic>{};
    void diff(String key, Object a, Object b) {
      if (a != b) changes[key] = b;
    }

    diff('title', original.title, edited.title);
    diff('description', original.description, edited.description);
    diff('from_minutes', _minutes(original.from), _minutes(edited.from));
    diff('to_minutes', _minutes(original.to), _minutes(edited.to));
    diff(
      'category',
      original.categoryKey ?? original.category.name,
      edited.categoryKey ?? edited.category.name,
    );
    diff('tipo', original.tipo.name, edited.tipo.name);
    diff('icon', original.icon, edited.icon);
    diff('color', original.color.value, edited.color.value);

    final oldD = DateTime(
      originalDay.year,
      originalDay.month,
      originalDay.day,
    );
    final newD = DateTime(newDay.year, newDay.month, newDay.day);
    final moves = oldD != newD;

    final add = addSharedWith
        .where((u) => u.isNotEmpty && u != owner && u != me)
        .toSet()
        .toList();

    if (changes.isEmpty && !moves && add.isEmpty) return false;

    try {
      await _cancelMine(eventId);
      await _db.collection(_col).add({
        'item_id': eventId,
        'item_type': itemType,
        'item_title': original.title,
        'owner_id': owner,
        'from_uid': me,
        'from_name': _displayName,
        'to_uid': owner,
        'old_date': Timestamp.fromDate(oldD),
        'new_date': Timestamp.fromDate(newD),
        'changes': changes,
        'add_shared_with': add,
        'add_shared_names': addSharedNames,
        'created_at': FieldValue.serverTimestamp(),
      });
      debugPrint(
        '📤 Propuesta de evento enviada | evento=$eventId dueño=$owner '
        'cambios=${changes.keys.toList()} mueve=$moves añadir=$add',
      );
      return true;
    } catch (e) {
      debugPrint('❌ Error enviando propuesta de evento: $e');
      return false;
    }
  }

  /// Si ya había mandado una propuesta para este evento, la sustituyo.
  Future<void> _cancelMine(String eventId) async {
    try {
      final snap = await _db
          .collection(_col)
          .where('item_id', isEqualTo: eventId)
          .where('from_uid', isEqualTo: _uid)
          .get();
      for (final d in snap.docs) {
        if (d.data()['item_type'] == itemType) await d.reference.delete();
      }
    } catch (e) {
      debugPrint('⚠️ No se pudo limpiar la propuesta anterior: $e');
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // RECIBIR
  // ══════════════════════════════════════════════════════════════════════════

  /// Propuestas sobre mis eventos pendientes de responder.
  Future<List<EventChangeProposal>> pendingForMe() async {
    if (_uid.isEmpty) return [];
    try {
      final snap = await _db
          .collection(_col)
          .where('to_uid', isEqualTo: _uid)
          .get();
      final list = snap.docs
          .where((d) => d.data()['item_type'] == itemType)
          .map((d) => EventChangeProposal.fromDoc(d.id, d.data()))
          .toList();
      return list;
    } catch (e) {
      debugPrint('❌ Error leyendo propuestas de eventos: $e');
      return [];
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // RESPONDER
  // ══════════════════════════════════════════════════════════════════════════

  /// Acepto: aplico los cambios a mi evento. Se propaga a todos los que lo
  /// tienen compartido (y a los nuevos de add_shared_with).
  Future<bool> accept(EventChangeProposal p) async {
    try {
      final ref = _db.collection('events').doc(p.eventId);
      final snap = await ref.get();
      final data = snap.data();
      if (data == null) {
        // El evento ya no existe: la propuesta sobra.
        await _delete(p.id);
        return false;
      }

      // Con quién queda compartido: lo que ya tenía + lo que se pide añadir.
      final current = List<String>.from(data['shared_with'] ?? const []);
      final merged = {...current, ...p.addSharedWith}.toList();

      final rows = await DBProvider.db.query(
        DBSchema.tableEvents,
        where: 'id = ?',
        whereArgs: [p.eventId],
        limit: '1',
      );

      if (rows.isNotEmpty) {
        // Camino normal: actualizar el evento local y guardarlo (lo sube).
        // Las columnas locales se llaman igual que los campos de 'changes'.
        final ev = EventRepository.instance.fromRow({
          ...rows.first,
          ...p.changes,
        });
        final updated = p.addSharedWith.isEmpty
            ? ev
            : ev.copyWith(sharedWith: merged);
        await EventRepository.instance.save(updated, p.newDay);
      } else {
        // No lo tengo en local: se aplica directamente en Firestore.
        await ref.set({
          ...p.changes,
          'date': Timestamp.fromDate(
            DateTime.utc(p.newDay.year, p.newDay.month, p.newDay.day),
          ),
          if (p.addSharedWith.isNotEmpty) ...{
            'shared_with': merged,
            'share_custom': true,
          },
          'updated_at': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      // Marca para que la Cloud Function avise al resto de afectados.
      await ref.set({
        'last_change_from_uid': p.fromUid,
        'last_change_from_name': p.fromName,
        'last_change_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await _delete(p.id);
      debugPrint('✅ Propuesta de evento aceptada | ${p.eventId}');
      return true;
    } catch (e) {
      debugPrint('❌ Error aceptando propuesta de evento: $e');
      return false;
    }
  }

  Future<void> reject(EventChangeProposal p) => _delete(p.id);

  Future<void> _delete(String id) async {
    try {
      await _db.collection(_col).doc(id).delete();
    } catch (e) {
      debugPrint('❌ Error borrando propuesta $id: $e');
    }
  }
}
