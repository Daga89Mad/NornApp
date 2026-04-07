// lib/models/friend_model.dart

class FriendModel {
  final String? id;
  final String name; // nombre real (del perfil Firebase)
  final String email; // email con el que se buscó
  final String alias; // alias personalizado (opcional)
  final String logo; // emoji elegido como avatar
  final String? firebaseUid; // UID de Firebase del amigo

  const FriendModel({
    this.id,
    required this.name,
    required this.email,
    this.alias = '',
    this.logo = '😊',
    this.firebaseUid,
  });

  /// Nombre que se mostrará: alias si existe, si no el name real.
  String get displayName => alias.isNotEmpty ? alias : name;
}
