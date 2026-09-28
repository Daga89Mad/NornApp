// lib/views/expenses/expenses_screen.dart
//
// Pantalla principal de GASTOS: listado de todos los proyectos de gastos en
// los que participo, agrupados en "En curso", "Próximos" y "Finalizados" y
// ordenados por fecha. Desde aquí se crean proyectos nuevos y se entra al
// desglose de cada uno.

import 'package:flutter/material.dart';
import 'package:nornapp/views/expenses/expense_project_detail_screen.dart';
import '../../core/expense_repository.dart';
import '../../models/expense_models.dart';
import 'expense_project_form_screen.dart';
import 'expense_widgets.dart';

enum _Filter { all, active, upcoming, finished }

class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  final _repo = ExpenseRepository.instance;
  late final Stream<List<ExpenseProject>> _stream = _repo.watchProjects();
  late ExpensePeople _people = ExpensePeople(myUid: _repo.uid);
  _Filter _filter = _Filter.all;

  @override
  void initState() {
    super.initState();
    ExpensePeople.load(_repo.uid).then((p) {
      if (mounted) setState(() => _people = p);
    });
    _generate();
  }

  /// Crea los periodos pendientes de las series periódicas.
  Future<void> _generate() async {
    final n = await _repo.generateDueInstances();
    if (!mounted || n == 0) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          n == 1
              ? 'Se ha creado 1 periodo nuevo'
              : 'Se han creado $n periodos nuevos',
        ),
        backgroundColor: ExpenseColors.primary,
      ),
    );
  }

  Future<void> _openCreate() async {
    final newId = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const ExpenseProjectFormScreen()),
    );
    if (newId == null || !mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ExpenseProjectDetailScreen(projectId: newId),
      ),
    );
  }

  void _openDetail(ExpenseProject p) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ExpenseProjectDetailScreen(projectId: p.id, initial: p),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // ORDEN Y AGRUPACIÓN
  // ══════════════════════════════════════════════════════════════════════════

  ({
    List<ExpenseProject> active,
    List<ExpenseProject> upcoming,
    List<ExpenseProject> finished,
  })
  _group(List<ExpenseProject> all) {
    final now = DateTime.now();
    final active = <ExpenseProject>[];
    final upcoming = <ExpenseProject>[];
    final finished = <ExpenseProject>[];
    for (final p in all) {
      switch (p.statusAt(now)) {
        case ExpenseProjectStatus.active:
          active.add(p);
          break;
        case ExpenseProjectStatus.upcoming:
          upcoming.add(p);
          break;
        case ExpenseProjectStatus.finished:
          finished.add(p);
          break;
      }
    }
    // En curso: el que empezó más recientemente primero.
    active.sort((a, b) => b.startDate.compareTo(a.startDate));
    // Próximos: el más cercano primero.
    upcoming.sort((a, b) => a.startDate.compareTo(b.startDate));
    // Finalizados: el que terminó más recientemente primero.
    finished.sort((a, b) => b.endDate.compareTo(a.endDate));
    return (active: active, upcoming: upcoming, finished: finished);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ExpenseColors.background,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: ExpenseColors.primary,
        foregroundColor: Colors.white,
        onPressed: _openCreate,
        icon: const Icon(Icons.add),
        label: const Text('Nuevo proyecto'),
      ),
      body: StreamBuilder<List<ExpenseProject>>(
        stream: _stream,
        builder: (context, snap) {
          final loading =
              snap.connectionState == ConnectionState.waiting && !snap.hasData;
          final all = snap.data ?? const <ExpenseProject>[];
          final g = _group(all);

          return RefreshIndicator(
            color: ExpenseColors.primary,
            onRefresh: _generate,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                _buildAppBar(g.active),
                SliverToBoxAdapter(child: _buildFilters(g)),
                if (snap.hasError)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: ExpenseEmptyState(
                      icon: Icons.cloud_off,
                      title: 'No se pudieron cargar los gastos',
                      subtitle: '${snap.error}',
                    ),
                  )
                else if (loading)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (all.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: ExpenseEmptyState(
                      icon: Icons.savings_outlined,
                      title: 'Todavía no hay proyectos de gastos',
                      subtitle:
                          'Crea uno para un viaje, la casa o los gastos del mes '
                          'y compártelo con tus amigos.',
                    ),
                  )
                else
                  ..._buildSections(g),
                const SliverToBoxAdapter(child: SizedBox(height: 110)),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildAppBar(List<ExpenseProject> active) {
    final myUid = _repo.uid;
    final myActiveTotal = active.fold<int>(
      0,
      (a, p) => a + (p.totalsByUid[myUid] ?? 0),
    );
    final activeTotal = active.fold<int>(0, (a, p) => a + p.totalCents);

    return SliverAppBar(
      pinned: true,
      expandedHeight: 190,
      backgroundColor: ExpenseColors.primary,
      foregroundColor: Colors.white,
      title: const Text('Gastos'),
      actions: [
        IconButton(
          tooltip: 'Comprobar periodos',
          icon: const Icon(Icons.sync),
          onPressed: _generate,
        ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        collapseMode: CollapseMode.pin,
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [ExpenseColors.primaryDark, ExpenseColors.accent],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          padding: EdgeInsets.fromLTRB(
            20,
            MediaQuery.of(context).padding.top + kToolbarHeight + 8,
            20,
            18,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: _HeaderStat(
                  label: 'En curso',
                  value: '${active.length}',
                  icon: Icons.play_circle_outline,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _HeaderStat(
                  label: 'Total en curso',
                  value: formatEuros(activeTotal),
                  icon: Icons.receipt_long_outlined,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _HeaderStat(
                  label: 'Has puesto',
                  value: formatEuros(myActiveTotal),
                  icon: Icons.person_outline,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilters(
    ({
      List<ExpenseProject> active,
      List<ExpenseProject> upcoming,
      List<ExpenseProject> finished,
    })
    g,
  ) {
    final total = g.active.length + g.upcoming.length + g.finished.length;
    Widget chip(_Filter f, String label, int count) {
      final sel = _filter == f;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text('$label · $count'),
          selected: sel,
          showCheckmark: false,
          selectedColor: ExpenseColors.primary,
          backgroundColor: Colors.white,
          side: BorderSide(
            color: sel ? ExpenseColors.primary : Colors.grey.shade300,
          ),
          labelStyle: TextStyle(
            color: sel ? Colors.white : Colors.grey.shade800,
            fontWeight: FontWeight.w600,
            fontSize: 12.5,
          ),
          onSelected: (_) => setState(() => _filter = f),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 4),
      child: Row(
        children: [
          chip(_Filter.all, 'Todos', total),
          chip(_Filter.active, 'En curso', g.active.length),
          chip(_Filter.upcoming, 'Próximos', g.upcoming.length),
          chip(_Filter.finished, 'Finalizados', g.finished.length),
        ],
      ),
    );
  }

  List<Widget> _buildSections(
    ({
      List<ExpenseProject> active,
      List<ExpenseProject> upcoming,
      List<ExpenseProject> finished,
    })
    g,
  ) {
    final sections = <(String, IconData, List<ExpenseProject>)>[
      if (_filter == _Filter.all || _filter == _Filter.active)
        ('En curso', Icons.play_circle_outline, g.active),
      if (_filter == _Filter.all || _filter == _Filter.upcoming)
        ('Próximos', Icons.schedule, g.upcoming),
      if (_filter == _Filter.all || _filter == _Filter.finished)
        ('Finalizados', Icons.flag_outlined, g.finished),
    ];

    final visible = sections.where((s) => s.$3.isNotEmpty).toList();
    if (visible.isEmpty) {
      return const [
        SliverToBoxAdapter(
          child: ExpenseEmptyState(
            icon: Icons.filter_alt_off_outlined,
            title: 'Nada por aquí',
            subtitle: 'No hay proyectos en este apartado.',
          ),
        ),
      ];
    }

    return [
      for (final s in visible) ...[
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(
              children: [
                Icon(s.$2, size: 16, color: ExpenseColors.primary),
                const SizedBox(width: 6),
                Text(
                  s.$1,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: ExpenseColors.primaryDark,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '${s.$3.length}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (ctx, i) => _ProjectCard(
                project: s.$3[i],
                people: _people,
                onTap: () => _openDetail(s.$3[i]),
              ),
              childCount: s.$3.length,
            ),
          ),
        ),
      ],
    ];
  }
}

// ════════════════════════════════════════════════════════════════════════════
// WIDGETS
// ════════════════════════════════════════════════════════════════════════════

class _HeaderStat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _HeaderStat({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.14),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.white70),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _ProjectCard extends StatelessWidget {
  final ExpenseProject project;
  final ExpensePeople people;
  final VoidCallback onTap;

  const _ProjectCard({
    required this.project,
    required this.people,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = project;
    final typeColor = ExpenseColors.forType(p.type);
    final status = p.statusAt(DateTime.now());
    final isSubtract = p.type == ExpenseProjectType.subtract;
    final remaining = p.remainingCents;
    final over = isSubtract && remaining < 0;

    return SoftCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [typeColor, typeColor.withOpacity(0.7)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  ExpenseColors.iconForType(p.type),
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Icon(
                          Icons.event_outlined,
                          size: 13,
                          color: Colors.grey.shade500,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            fmtRange(p.startDate, p.endDate),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    formatEuros(isSubtract ? remaining : p.totalCents),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: over ? ExpenseColors.negative : Colors.black87,
                    ),
                  ),
                  Text(
                    isSubtract ? (over ? 'excedido' : 'quedan') : 'gastado',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                  ),
                ],
              ),
            ],
          ),
          if (isSubtract) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: p.budgetUsedRatio,
                minHeight: 7,
                backgroundColor: typeColor.withOpacity(0.12),
                valueColor: AlwaysStoppedAnimation<Color>(
                  over ? ExpenseColors.negative : typeColor,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Gastado ${formatEuros(p.totalCents)} de ${formatEuros(p.budgetCents)}',
              style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    StatusChip(status: status),
                    InfoChip(
                      icon: isSubtract
                          ? Icons.remove_circle_outline
                          : Icons.add_circle_outline,
                      label: p.type.shortLabel,
                      color: typeColor,
                    ),
                    if (p.isRecurring)
                      InfoChip(
                        icon: Icons.autorenew,
                        label: p.recurrence.label,
                        color: ExpenseColors.primary,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              AvatarStack(uids: p.members, people: people, project: p),
            ],
          ),
        ],
      ),
    );
  }
}
