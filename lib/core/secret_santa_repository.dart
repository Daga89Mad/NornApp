// lib/core/secret_santa_repository.dart
//
// Acceso a Firestore del AMIGO INVISIBLE (esquema en
// models/secret_santa_models.dart).
//
// · Como en Gastos, se escribe directo en Firestore (caché offline incluida).
// · El sorteo NO se hace en el móvil: el organizador pone status = 'drawing'
//   y la Cloud Function onSecretSantaDraw reparte y guarda cada asignación en
//   un documento que solo puede leer quien regala.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/secret_santa_models.dart';

class SecretSantaRepository {
  SecretSantaRepository._();
  static final SecretSantaRepository instance = SecretSantaRepository._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  static const String _gamesCol = 'secret_santa_games';

  String get uid => FirebaseAuth.instance.currentUser?.uid ?? '';
  String get myName {
    final u = FirebaseAuth.instance.currentUser;
    final n = u?.displayName?.trim() ?? '';
    if (n.isNotEmpty) return n;
    return u?.email?.split('@').first ?? 'Yo';
  }

  CollectionReference<Map<String, dynamic>> get _games =>
      _db.collection(_gamesCol);

  // ── Lectura ────────────────────────────────────────────────────────────────

  Stream<List<SecretSantaGame>> watchGames() {
    if (uid.isEmpty) return Stream.value(const []);
    return _games
        .where('invited', arrayContains: uid)
        .snapshots()
        .map((s) => s.docs.map(SecretSantaGame.fromDoc).toList());
  }

  Stream<SecretSantaGame?> watchGame(String id) => _games
      .doc(id)
      .snapshots()
      .map((d) => d.exists ? SecretSantaGame.fromDoc(d) : null);

  Stream<Map<String, SecretSantaWishlist>> watchWishlists(String id) => _games
      .doc(id)
      .collection('wishlists')
      .snapshots()
      .map(
        (s) => {
          for (final d in s.docs) d.id: SecretSantaWishlist.fromDoc(d),
        },
      );

  /// Mi asignación (null hasta que se haga el sorteo).
  Stream<SecretSantaAssignment?> watchMyAssignment(String id) => _games
      .doc(id)
      .collection('assignments')
      .doc(uid)
      .snapshots()
      .map((d) => d.exists ? SecretSantaAssignment.fromDoc(d) : null)
      .handleError((_) {});

  // ── Escritura ──────────────────────────────────────────────────────────────

  /// [invitedNames]: uid → nombre de los amigos invitados.
  Future<String> createGame({
    required String name,
    required int budgetCents,
    DateTime? eventDate,
    String notes = '',
    required Map<String, String> invitedNames,
    bool joinMyself = true,
  }) async {
    final ref = _games.doc();
    final names = <String, String>{...invitedNames, uid: myName};
    await ref.set({
      'owner_id': uid,
      'name': name.trim(),
      'budget_cents': budgetCents,
      'event_date': eventDate != null ? Timestamp.fromDate(eventDate) : null,
      'notes': notes.trim(),
      'invited': names.keys.toList(),
      'participants': joinMyself ? [uid] : <String>[],
      'names': names,
      'status': 'open',
      'created_at': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  Future<void> updateGame(
    String id, {
    required String name,
    required int budgetCents,
    DateTime? eventDate,
    String notes = '',
    required Map<String, String> invitedNames,
    required List<String> currentParticipants,
  }) async {
    final names = <String, String>{...invitedNames, uid: myName};
    final invited = names.keys.toList();
    await _games.doc(id).update({
      'name': name.trim(),
      'budget_cents': budgetCents,
      'event_date': eventDate != null ? Timestamp.fromDate(eventDate) : null,
      'notes': notes.trim(),
      'invited': invited,
      'names': names,
      // Si quito a alguien de los invitados, también sale del sorteo.
      'participants': currentParticipants
          .where((p) => invited.contains(p))
          .toList(),
    });
  }

  Future<void> join(String id) => _games.doc(id).update({
    'participants': FieldValue.arrayUnion([uid]),
    'names.$uid': myName,
  });

  Future<void> leave(String id) => _games.doc(id).update({
    'participants': FieldValue.arrayRemove([uid]),
  });

  /// Pide el sorteo a la Cloud Function.
  Future<void> requestDraw(String id) =>
      _games.doc(id).update({'status': 'drawing'});

  Future<void> deleteGame(String id) => _games.doc(id).delete();

  Future<void> saveWishlist(String id, List<String> items, String note) =>
      _games.doc(id).collection('wishlists').doc(uid).set({
        'items': items.map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
        'note': note.trim(),
        'updated_at': FieldValue.serverTimestamp(),
      });
}
