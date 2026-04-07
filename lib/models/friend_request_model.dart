// lib/models/friend_request_model.dart

enum FriendRequestStatus { pending, accepted, rejected }

class FriendRequestModel {
  final String? id;
  final String fromUid;
  final String fromName;
  final String fromEmail;
  final String fromLogo;
  final String toUid;
  final String toEmail;
  final FriendRequestStatus status;

  const FriendRequestModel({
    this.id,
    required this.fromUid,
    required this.fromName,
    required this.fromEmail,
    required this.fromLogo,
    required this.toUid,
    required this.toEmail,
    this.status = FriendRequestStatus.pending,
  });
}
