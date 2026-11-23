// lib/models/secret_santa_models.dart
//
// AMIGO INVISIBLE — esquema en Firestore:
//
// secret_santa_games/{gameId}
//   owner_id, name, budget_cents, event_date (Timestamp?), notes,
//   invited: [uid]       → quién lo ve (organizador + amigos invitados)
//   participants: [uid]  → quién se ha apuntado al sorteo
//   names: {uid: nombre} → para mostrar a gente que no es amiga mía
//   status: open | drawing | drawn
//   draw_error, created_at, drawn_at
//
// secret_santa_games/{gameId}/wishlists/{uid}
//   items: [String], note, updated_at
//
// secret_santa_games/{gameId}/assignments/{giverUid}   (solo lo lee giverUid)
//   giver_uid, receiver_uid, receiver_name

import 'package:cloud_firestore/cloud_firestore.dart';

enum SecretSantaStatus { open, drawing, drawn }

SecretSantaStatus _statusFrom(String? s) {
  switch (s) {
    case 'drawing':
      return SecretSantaStatus.drawing;
    case 'drawn':
      return SecretSantaStatus.drawn;
    default:
      return SecretSantaStatus.open;
  }
}

String secretSantaStatusName(SecretSantaStatus s) {
  switch (s) {
    case SecretSantaStatus.open:
      return 'open';
    case SecretSantaStatus.drawing:
      return 'drawing';
    case SecretSantaStatus.drawn:
      return 'drawn';
  }
}

class SecretSantaGame {
  final String id;
  final String ownerId;
  final String name;
  final int budgetCents;
  final DateTime? eventDate;
  final String notes;
  final List<String> invited;
  final List<String> participants;
  final Map<String, String> names;
  final SecretSantaStatus status;
  final String drawError;
  final DateTime? createdAt;
  final DateTime? drawnAt;

  const SecretSantaGame({
    required this.id,
    required this.ownerId,
    required this.name,
    required this.budgetCents,
    this.eventDate,
    this.notes = '',
    this.invited = const [],
    this.participants = const [],
    this.names = const {},
    this.status = SecretSantaStatus.open,
    this.drawError = '',
    this.createdAt,
    this.drawnAt,
  });

  static const int minPlayers = 3;

  bool isOwner(String uid) => ownerId == uid;
  bool hasJoined(String uid) => participants.contains(uid);
  bool get canDraw =>
      status == SecretSantaStatus.open && participants.length >= minPlayers;

  static DateTime? _date(dynamic v) => v is Timestamp ? v.toDate() : null;

  factory SecretSantaGame.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? const <String, dynamic>{};
    return SecretSantaGame(
      id: d.id,
      ownerId: (m['owner_id'] as String?) ?? '',
      name: (m['name'] as String?) ?? 'Amigo invisible',
      budgetCents: (m['budget_cents'] as num?)?.toInt() ?? 0,
      eventDate: _date(m['event_date']),
      notes: (m['notes'] as String?) ?? '',
      invited: List<String>.from((m['invited'] as List?) ?? const []),
      participants: List<String>.from((m['participants'] as List?) ?? const []),
      names: ((m['names'] as Map?) ?? const {}).map(
        (k, v) => MapEntry(k.toString(), (v ?? '').toString()),
      ),
      status: _statusFrom(m['status'] as String?),
      drawError: (m['draw_error'] as String?) ?? '',
      createdAt: _date(m['created_at']),
      drawnAt: _date(m['drawn_at']),
    );
  }
}

class SecretSantaWishlist {
  final String uid;
  final List<String> items;
  final String note;

  const SecretSantaWishlist({
    required this.uid,
    this.items = const [],
    this.note = '',
  });

  bool get isEmpty => items.isEmpty && note.trim().isEmpty;

  factory SecretSantaWishlist.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> d,
  ) {
    final m = d.data() ?? const <String, dynamic>{};
    return SecretSantaWishlist(
      uid: d.id,
      items: List<String>.from((m['items'] as List?) ?? const []),
      note: (m['note'] as String?) ?? '',
    );
  }
}

class SecretSantaAssignment {
  final String receiverUid;
  final String receiverName;

  const SecretSantaAssignment({
    required this.receiverUid,
    required this.receiverName,
  });

  factory SecretSantaAssignment.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> d,
  ) {
    final m = d.data() ?? const <String, dynamic>{};
    return SecretSantaAssignment(
      receiverUid: (m['receiver_uid'] as String?) ?? '',
      receiverName: (m['receiver_name'] as String?) ?? '',
    );
  }
}
