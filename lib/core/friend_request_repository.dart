// lib/core/friend_request_repository.dart
//
// Gestiona solicitudes de amistad en Firestore.
// El flujo es:
//   A busca B → sendRequest() → Firestore crea solicitud → FCM notifica a B
//   B acepta → acceptRequest() → ambos se guardan como amigos
//   B rechaza → rejectRequest() → solicitud marcada como rejected

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../models/friend_request_model.dart';
import '../models/friend_model.dart';
import 'friend_repository.dart';

class FriendRequestRepository {
  FriendRequestRepository._();
  static final FriendRequestRepository instance = FriendRequestRepository._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  static const String _col = 'friend_requests';

  // ── Serialización ──────────────────────────────────────────────────────────

  FriendRequestModel _fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return FriendRequestModel(
      id: doc.id,
      fromUid: data['from_uid'] ?? '',
      fromName: data['from_name'] ?? '',
      fromEmail: data['from_email'] ?? '',
      fromLogo: data['from_logo'] ?? '😊',
      toUid: data['to_uid'] ?? '',
      toEmail: data['to_email'] ?? '',
      status: _parseStatus(data['status']),
    );
  }

  FriendRequestStatus _parseStatus(String? s) {
    switch (s) {
      case 'accepted':
        return FriendRequestStatus.accepted;
      case 'rejected':
        return FriendRequestStatus.rejected;
      default:
        return FriendRequestStatus.pending;
    }
  }

  // ── Enviar solicitud ───────────────────────────────────────────────────────

  /// Crea una solicitud en Firestore.
  /// Devuelve null si ya existe una solicitud pendiente entre estos usuarios.
  /// [toUid]   UID de Firebase del destinatario
  /// [toEmail] email del destinatario
  /// [fromLogo] logo que el emisor eligió para identificar al amigo
  ///
  /// Los datos del EMISOR (from_*) se obtienen siempre desde FirebaseAuth
  /// y user_profiles para evitar que se confundan con los del destinatario.
  Future<String?> sendRequest({
    required String toUid,
    required String toEmail,
    required String fromLogo,
  }) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    final fromUid = currentUser?.uid;
    if (fromUid == null) return null;

    // Evitar enviarse solicitud a uno mismo
    if (fromUid == toUid) return 'self';

    // Obtener nombre del EMISOR desde user_profiles
    final fromEmail = (currentUser!.email ?? '').toLowerCase();
    String fromName = currentUser.displayName ?? fromEmail.split('@').first;
    try {
      final snap = await _db.collection('user_profiles').doc(fromUid).get();
      final n = snap.data()?['name'] as String?;
      if (n != null && n.isNotEmpty) fromName = n;
    } catch (_) {}

    // Verificar si ya existe solicitud pendiente
    final existing = await _db
        .collection(_col)
        .where('from_uid', isEqualTo: fromUid)
        .where('to_uid', isEqualTo: toUid)
        .where('status', isEqualTo: 'pending')
        .get();
    if (existing.docs.isNotEmpty) return 'already_sent';

    // Verificar si ya son amigos
    final alreadyFriends = await FriendRepository.instance.getAll();
    if (alreadyFriends.any((f) => f.firebaseUid == toUid)) {
      return 'already_friends';
    }

    // Crear solicitud con datos correctos del EMISOR (no del destinatario)
    final ref = await _db.collection(_col).add({
      'from_uid': fromUid,
      'from_name': fromName,
      'from_email': fromEmail,
      'from_logo': fromLogo,
      'to_uid': toUid,
      'to_email': toEmail,
      'status': 'pending',
      'created_at': FieldValue.serverTimestamp(),
    });

    debugPrint(
      'Solicitud enviada: ' + fromName + ' -> ' + toEmail + ' (' + ref.id + ')',
    );
    return ref.id;
  }

  // ── Consultas ──────────────────────────────────────────────────────────────

  /// Solicitudes RECIBIDAS pendientes por el usuario actual.
  Future<List<FriendRequestModel>> getPendingReceived() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return [];

    final snap = await _db
        .collection(_col)
        .where('to_uid', isEqualTo: uid)
        .where('status', isEqualTo: 'pending')
        .orderBy('created_at', descending: true)
        .get();

    return snap.docs.map(_fromDoc).toList();
  }

  /// Solicitudes ENVIADAS pendientes por el usuario actual.
  Future<List<FriendRequestModel>> getPendingSent() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return [];

    final snap = await _db
        .collection(_col)
        .where('from_uid', isEqualTo: uid)
        .where('status', isEqualTo: 'pending')
        .orderBy('created_at', descending: true)
        .get();

    return snap.docs.map(_fromDoc).toList();
  }

  // ── Aceptar ────────────────────────────────────────────────────────────────

  Future<void> acceptRequest(FriendRequestModel request) async {
    if (request.id == null) return;

    // 1. Marcar como aceptada
    await _db.collection(_col).doc(request.id).update({'status': 'accepted'});

    // 2. Guardar al emisor como amigo del receptor (yo)
    final meAsFriend = FriendModel(
      name: request.fromName,
      email: request.fromEmail,
      logo: request.fromLogo,
      firebaseUid: request.fromUid,
    );
    await FriendRepository.instance.save(meAsFriend);

    debugPrint('Solicitud aceptada: ' + request.fromName);
  }

  // ── Rechazar ───────────────────────────────────────────────────────────────

  Future<void> rejectRequest(FriendRequestModel request) async {
    if (request.id == null) return;
    await _db.collection(_col).doc(request.id).update({'status': 'rejected'});
    debugPrint('❌ Solicitud rechazada: ${request.fromName}');
  }

  /// Solicitudes enviadas que ya fueron ACEPTADAS — para sincronizar la
  /// relación inversa cuando A abre la app.
  Future<List<FriendRequestModel>> getAcceptedSent() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return [];

    final snap = await _db
        .collection(_col)
        .where('from_uid', isEqualTo: uid)
        .where('status', isEqualTo: 'accepted')
        .get();

    return snap.docs.map(_fromDoc).toList();
  }

  // ── Cancelar (emisor cancela su propia solicitud) ──────────────────────────

  Future<void> cancelRequest(String requestId) async {
    await _db.collection(_col).doc(requestId).delete();
    debugPrint('🗑️ Solicitud cancelada: $requestId');
  }

  // ── Listener en tiempo real ────────────────────────────────────────────────

  /// Stream de solicitudes recibidas pendientes — para mostrar badge en UI.
  Stream<int> pendingReceivedCount() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return Stream.value(0);

    return _db
        .collection(_col)
        .where('to_uid', isEqualTo: uid)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((snap) => snap.docs.length);
  }
}
