// lib/views/utilities_screen.dart
//
// UTILIDADES: agrupa Gastos, Diario y Amigo invisible (antes Gastos y Diario
// estaban sueltos en el menú principal).

import 'package:flutter/material.dart';
import 'package:nornapp/views/diary_screen.dart';
import 'package:nornapp/views/expenses/expenses_screen.dart';
import 'package:nornapp/views/secret_santa/secret_santa_screen.dart';

class UtilitiesScreen extends StatelessWidget {
  const UtilitiesScreen({super.key});

  static const Color _primary = Color(0xFF3949AB);
  static const Color _background = Color(0xFFF4F5FB);

  void _push(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final items = <_UtilityItem>[
      _UtilityItem(
        icon: Icons.account_balance_wallet_outlined,
        title: 'Gastos',
        subtitle: 'Proyectos de gastos compartidos y quién debe a quién',
        colors: const [Color(0xFF5E35B1), Color(0xFF7E57C2)],
        onTap: () => _push(context, const ExpensesScreen()),
      ),
      _UtilityItem(
        icon: Icons.menu_book_outlined,
        title: 'Diario',
        subtitle: 'Tus notas personales del día a día',
        colors: const [Color(0xFF00897B), Color(0xFF26A69A)],
        onTap: () => _push(context, const DiaryScreen()),
      ),
      _UtilityItem(
        icon: Icons.card_giftcard_rounded,
        title: 'Amigo invisible',
        subtitle: 'Organiza el sorteo de regalos con tus amigos',
        colors: const [Color(0xFFC62828), Color(0xFFE53935)],
        onTap: () => _push(context, const SecretSantaScreen()),
      ),
    ];

    return Scaffold(
      backgroundColor: _background,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 150,
            backgroundColor: _primary,
            foregroundColor: Colors.white,
            title: const Text('Utilidades'),
            flexibleSpace: FlexibleSpaceBar(
              collapseMode: CollapseMode.pin,
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF283593), Color(0xFF5C6BC0)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 22),
                alignment: Alignment.bottomLeft,
                child: const Text(
                  'Herramientas para organizarte con los tuyos',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
            sliver: SliverList.separated(
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 14),
              itemBuilder: (_, i) => _UtilityCard(item: items[i]),
            ),
          ),
        ],
      ),
    );
  }
}

class _UtilityItem {
  final IconData icon;
  final String title;
  final String subtitle;
  final List<Color> colors;
  final VoidCallback onTap;

  const _UtilityItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.colors,
    required this.onTap,
  });
}

class _UtilityCard extends StatelessWidget {
  final _UtilityItem item;
  const _UtilityCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      elevation: 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: item.onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: item.colors.first.withOpacity(0.10),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: item.colors,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(item.icon, color: Colors.white, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }
}
