// lib/views/expenses/expense_widgets.dart
//
// Piezas comunes de las pantallas de GASTOS: colores, formato de fechas en
// español (sin depender del locale, como el resto de la app), nombres y
// avatares de los miembros, chips y estado vacío.

import 'package:flutter/material.dart';
import '../../core/friend_repository.dart';
import '../../models/expense_models.dart';
import '../../models/friend_model.dart';

// ════════════════════════════════════════════════════════════════════════════
// COLORES
// ════════════════════════════════════════════════════════════════════════════

class ExpenseColors {
  ExpenseColors._();
  static const Color primary = Color(0xFF5E35B1);
  static const Color primaryDark = Color(0xFF4527A0);
  static const Color accent = Color(0xFF7E57C2);
  static const Color background = Color(0xFFF5F3FA);
  static const Color sum = Color(0xFF1E88E5);
  static const Color subtract = Color(0xFFF4511E);
  static const Color positive = Color(0xFF2E7D32);
  static const Color negative = Color(0xFFC62828);

  static Color forType(ExpenseProjectType t) =>
      t == ExpenseProjectType.sum ? sum : subtract;

  static IconData iconForType(ExpenseProjectType t) =>
      t == ExpenseProjectType.sum
      ? Icons.stacked_line_chart_rounded
      : Icons.account_balance_wallet_outlined;

  static const List<Color> _people = [
    Color(0xFF5E35B1),
    Color(0xFF00897B),
    Color(0xFFEF6C00),
    Color(0xFF1E88E5),
    Color(0xFFD81B60),
    Color(0xFF43A047),
    Color(0xFF6D4C41),
    Color(0xFF3949AB),
  ];

  /// Color estable para cada persona (mismo uid → mismo color).
  static Color forPerson(String uid) {
    var h = 0;
    for (final c in uid.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return _people[h % _people.length];
  }
}

// ════════════════════════════════════════════════════════════════════════════
// FECHAS
// ════════════════════════════════════════════════════════════════════════════

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
const _dias = [
  'Lunes',
  'Martes',
  'Miércoles',
  'Jueves',
  'Viernes',
  'Sábado',
  'Domingo',
];

/// 12 oct 2026
String fmtDate(DateTime d) => '${d.day} ${_meses[d.month]} ${d.year}';

/// 12 oct
String fmtDateShort(DateTime d) => '${d.day} ${_meses[d.month]}';

/// Lunes, 12 oct (y el año si no es el actual)
String fmtDayHeader(DateTime d) {
  final base = '${_dias[d.weekday - 1]}, ${d.day} ${_meses[d.month]}';
  return d.year == DateTime.now().year ? base : '$base ${d.year}';
}

/// 1 – 31 oct 2026 · 28 sep – 4 oct 2026 · 28 dic 2026 – 3 ene 2027
String fmtRange(DateTime a, DateTime b) {
  if (a.year == b.year && a.month == b.month && a.day == b.day) {
    return fmtDate(a);
  }
  if (a.year != b.year) return '${fmtDate(a)} – ${fmtDate(b)}';
  if (a.month != b.month) {
    return '${fmtDateShort(a)} – ${fmtDateShort(b)} ${b.year}';
  }
  return '${a.day} – ${b.day} ${_meses[b.month]} ${b.year}';
}

// ════════════════════════════════════════════════════════════════════════════
// PERSONAS (nombres y avatares)
// ════════════════════════════════════════════════════════════════════════════

/// Resuelve cómo se muestra cada uid: "Tú", el alias que yo le he puesto en
/// Amigos o, si no es amigo mío, el nombre guardado en el proyecto.
class ExpensePeople {
  final String myUid;
  final Map<String, FriendModel> friendsByUid;

  const ExpensePeople({required this.myUid, this.friendsByUid = const {}});

  static Future<ExpensePeople> load(String myUid) async {
    try {
      final friends = await FriendRepository.instance.getAll();
      return ExpensePeople(
        myUid: myUid,
        friendsByUid: {
          for (final f in friends)
            if (f.firebaseUid != null && f.firebaseUid!.isNotEmpty)
              f.firebaseUid!: f,
        },
      );
    } catch (_) {
      return ExpensePeople(myUid: myUid);
    }
  }

  List<FriendModel> get friends =>
      friendsByUid.values.toList()
        ..sort((a, b) => a.displayName.compareTo(b.displayName));

  String name(String uid, {ExpenseProject? project, String fallback = ''}) {
    if (uid == myUid) return 'Tú';
    final f = friendsByUid[uid];
    if (f != null) return f.displayName;
    final n = project?.memberNames[uid];
    if (n != null && n.isNotEmpty) return n;
    return fallback.isNotEmpty ? fallback : 'Alguien';
  }

  String? emoji(String uid) => friendsByUid[uid]?.logo;
}

class PersonAvatar extends StatelessWidget {
  final String uid;
  final ExpensePeople people;
  final ExpenseProject? project;
  final double size;
  final bool border;

  const PersonAvatar({
    super.key,
    required this.uid,
    required this.people,
    this.project,
    this.size = 34,
    this.border = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = ExpenseColors.forPerson(uid);
    final emoji = people.emoji(uid);
    final name = uid == people.myUid
        ? (project?.memberNames[uid] ?? 'Yo')
        : people.name(uid, project: project);
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: emoji != null ? color.withOpacity(0.14) : color,
        shape: BoxShape.circle,
        border: border ? Border.all(color: Colors.white, width: 2) : null,
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

/// Avatares solapados (máx. [max]) + "+N".
class AvatarStack extends StatelessWidget {
  final List<String> uids;
  final ExpensePeople people;
  final ExpenseProject? project;
  final double size;
  final int max;

  const AvatarStack({
    super.key,
    required this.uids,
    required this.people,
    this.project,
    this.size = 28,
    this.max = 4,
  });

  @override
  Widget build(BuildContext context) {
    final shown = uids.take(max).toList();
    final extra = uids.length - shown.length;
    final step = size * 0.68;
    final count = shown.length + (extra > 0 ? 1 : 0);
    final width = count == 0 ? 0.0 : size + step * (count - 1);

    return SizedBox(
      width: width,
      height: size,
      child: Stack(
        children: [
          for (var i = 0; i < shown.length; i++)
            Positioned(
              left: i * step,
              child: PersonAvatar(
                uid: shown[i],
                people: people,
                project: project,
                size: size,
                border: true,
              ),
            ),
          if (extra > 0)
            Positioned(
              left: shown.length * step,
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                alignment: Alignment.center,
                child: Text(
                  '+$extra',
                  style: TextStyle(
                    fontSize: size * 0.36,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey.shade800,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// CHIPS / BADGES
// ════════════════════════════════════════════════════════════════════════════

class InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool onDark;

  const InfoChip({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    this.onDark = false,
  });

  @override
  Widget build(BuildContext context) {
    final fg = onDark ? Colors.white : color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: onDark ? Colors.white.withOpacity(0.18) : color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: fg),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

class StatusChip extends StatelessWidget {
  final ExpenseProjectStatus status;
  final bool onDark;

  const StatusChip({super.key, required this.status, this.onDark = false});

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case ExpenseProjectStatus.upcoming:
        return InfoChip(
          icon: Icons.schedule,
          label: 'Próximo',
          color: const Color(0xFF3949AB),
          onDark: onDark,
        );
      case ExpenseProjectStatus.active:
        return InfoChip(
          icon: Icons.play_circle_outline,
          label: 'En curso',
          color: ExpenseColors.positive,
          onDark: onDark,
        );
      case ExpenseProjectStatus.finished:
        return InfoChip(
          icon: Icons.flag_outlined,
          label: 'Finalizado',
          color: Colors.grey.shade700,
          onDark: onDark,
        );
    }
  }
}

// ════════════════════════════════════════════════════════════════════════════
// ESTADO VACÍO
// ════════════════════════════════════════════════════════════════════════════

class ExpenseEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const ExpenseEmptyState({
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
              color: ExpenseColors.primary.withOpacity(0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 40, color: ExpenseColors.accent),
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

/// Tarjeta blanca redondeada con sombra suave (base del estilo de Gastos).
class SoftCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const SoftCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.margin = const EdgeInsets.only(bottom: 10),
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: ExpenseColors.primary.withOpacity(0.06),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}
