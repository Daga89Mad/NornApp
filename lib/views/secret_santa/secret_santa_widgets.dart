// lib/views/secret_santa/secret_santa_widgets.dart
//
// Piezas comunes del AMIGO INVISIBLE: colores, formato de importes y
// nombres/avatares de los jugadores.

import 'package:flutter/material.dart';
import '../../core/friend_repository.dart';
import '../../models/friend_model.dart';
import '../../models/secret_santa_models.dart';

class SantaColors {
  SantaColors._();
  static const Color primary = Color(0xFFC62828);
  static const Color primaryDark = Color(0xFF8E0000);
  static const Color accent = Color(0xFFE53935);
  static const Color green = Color(0xFF2E7D32);
  static const Color gold = Color(0xFFF9A825);
  static const Color background = Color(0xFFFBF5F4);

  static const LinearGradient header = LinearGradient(
    colors: [Color(0xFF8E0000), Color(0xFFC62828), Color(0xFFE53935)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const List<Color> _people = [
    Color(0xFFC62828),
    Color(0xFF2E7D32),
    Color(0xFFEF6C00),
    Color(0xFF1E88E5),
    Color(0xFF6A1B9A),
    Color(0xFF00897B),
    Color(0xFF6D4C41),
    Color(0xFFAD1457),
  ];

  static Color forPerson(String uid) {
    var h = 0;
    for (final c in uid.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return _people[h % _people.length];
  }
}

/// 2000 → "20 €" · 2050 → "20,50 €"
String fmtBudget(int cents) {
  if (cents <= 0) return 'Sin límite';
  final euros = cents ~/ 100;
  final rest = cents % 100;
  return rest == 0
      ? '$euros €'
      : '$euros,${rest.toString().padLeft(2, '0')} €';
}

/// "20", "20,5", "20.50 €" → céntimos (null si no es válido).
int? parseBudget(String text) {
  final t = text.replaceAll('€', '').replaceAll(' ', '').replaceAll(',', '.');
  if (t.isEmpty) return 0;
  final v = double.tryParse(t);
  if (v == null || v < 0) return null;
  return (v * 100).round();
}

const _meses = [
  '',
  'ene',
  'feb',
  'mar',
  'abr',
  'may',
  'jun',
  'jul',
  'ago',
  'sep',
  'oct',
  'nov',
  'dic',
];

String fmtSantaDate(DateTime d) => '${d.day} ${_meses[d.month]} ${d.year}';

/// Nombres para mostrar: "Tú", el alias de Amigos o el nombre del juego.
class SantaPeople {
  final String myUid;
  final Map<String, FriendModel> friendsByUid;

  const SantaPeople({required this.myUid, this.friendsByUid = const {}});

  static Future<SantaPeople> load(String myUid) async {
    try {
      final friends = await FriendRepository.instance.getAll();
      return SantaPeople(
        myUid: myUid,
        friendsByUid: {
          for (final f in friends)
            if (f.firebaseUid != null && f.firebaseUid!.isNotEmpty)
              f.firebaseUid!: f,
        },
      );
    } catch (_) {
      return SantaPeople(myUid: myUid);
    }
  }

  List<FriendModel> get friends =>
      friendsByUid.values.toList()
        ..sort((a, b) => a.displayName.compareTo(b.displayName));

  String name(String uid, {SecretSantaGame? game, bool me = true}) {
    if (me && uid == myUid) return 'Tú';
    final f = friendsByUid[uid];
    if (f != null) return f.displayName;
    final n = game?.names[uid];
    if (n != null && n.isNotEmpty) return n;
    return 'Alguien';
  }

  String? emoji(String uid) => friendsByUid[uid]?.logo;
}

class SantaAvatar extends StatelessWidget {
  final String uid;
  final SantaPeople people;
  final SecretSantaGame? game;
  final double size;

  const SantaAvatar({
    super.key,
    required this.uid,
    required this.people,
    this.game,
    this.size = 40,
  });

  @override
  Widget build(BuildContext context) {
    final color = SantaColors.forPerson(uid);
    final emoji = people.emoji(uid);
    final name = people.name(uid, game: game, me: false);
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: emoji != null ? color.withOpacity(0.14) : color,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        emoji ?? initial,
        style: TextStyle(
          fontSize: emoji != null ? size * 0.5 : size * 0.42,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }
}

class SantaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool onDark;

  const SantaChip({
    super.key,
    required this.icon,
    required this.label,
    this.color = SantaColors.primary,
    this.onDark = false,
  });

  @override
  Widget build(BuildContext context) {
    final fg = onDark ? Colors.white : color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: onDark ? Colors.white.withOpacity(0.18) : color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

class SantaStatusChip extends StatelessWidget {
  final SecretSantaStatus status;
  final bool onDark;
  const SantaStatusChip({super.key, required this.status, this.onDark = false});

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case SecretSantaStatus.open:
        return SantaChip(
          icon: Icons.how_to_reg_outlined,
          label: 'Apuntándose',
          color: SantaColors.gold,
          onDark: onDark,
        );
      case SecretSantaStatus.drawing:
        return SantaChip(
          icon: Icons.casino_outlined,
          label: 'Sorteando…',
          color: SantaColors.accent,
          onDark: onDark,
        );
      case SecretSantaStatus.drawn:
        return SantaChip(
          icon: Icons.check_circle_outline,
          label: 'Sorteado',
          color: SantaColors.green,
          onDark: onDark,
        );
    }
  }
}

class SantaCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const SantaCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: SantaColors.primary.withOpacity(0.07),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
  }
}

class SantaEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const SantaEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle = '',
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              color: SantaColors.primary.withOpacity(0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 40, color: SantaColors.accent),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
          ],
        ],
      ),
    );
  }
}
