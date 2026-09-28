// lib/views/expenses/expense_project_detail_screen.dart
//
// Desglose de un proyecto de gastos:
//   · Cabecera con fechas, tipo, periodicidad, total / restante y miembros.
//   · Pestaña "Gastos": todos los gastos agrupados por día y ordenados por
//     fecha (más recientes primero o al revés).
//   · Pestaña "Totales": cuánto ha puesto cada uno y, en los de tipo Sumar,
//     las cuentas para quedar en paz (quién paga a quién).
//
// Todo en tiempo real: si otro miembro añade un gasto, aparece al momento.

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/expense_repository.dart';
import '../../core/week_dates.dart';
import '../../models/expense_models.dart';
import 'expense_project_form_screen.dart';
import 'expense_widgets.dart';

class ExpenseProjectDetailScreen extends StatefulWidget {
  final String projectId;
  final ExpenseProject? initial;

  const ExpenseProjectDetailScreen({
    super.key,
    required this.projectId,
    this.initial,
  });

  @override
  State<ExpenseProjectDetailScreen> createState() =>
      _ExpenseProjectDetailScreenState();
}

class _ExpenseProjectDetailScreenState
    extends State<ExpenseProjectDetailScreen> {
  final _repo = ExpenseRepository.instance;
  late final Stream<ExpenseProject?> _projectStream = _repo.watchProject(
    widget.projectId,
  );
  late final Stream<ExpenseListSnapshot> _expensesStream = _repo.watchExpenses(
    widget.projectId,
  );
  late ExpensePeople _people = ExpensePeople(myUid: _repo.uid);

  bool _newestFirst = true;
  bool? _seriesActive;
  bool _seriesRequested = false;
  String _lastReconcile = '';
  bool _closing = false;

  /// Gastos borrados con el gesto de deslizar, ocultos hasta que llega la
  /// confirmación de Firestore (Dismissible exige quitarlos al instante).
  final Set<String> _hiddenIds = {};

  String get _myUid => _repo.uid;

  @override
  void initState() {
    super.initState();
    ExpensePeople.load(_myUid).then((p) {
      if (mounted) setState(() => _people = p);
    });
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? ExpenseColors.negative : null,
      ),
    );
  }

  void _ensureSeriesLoaded(ExpenseProject p) {
    if (_seriesRequested || p.seriesId.isEmpty) return;
    _seriesRequested = true;
    _repo.getSeries(p.seriesId).then((s) {
      if (mounted) setState(() => _seriesActive = s?.active ?? false);
    });
  }

  /// Corrige los totales agregados si no cuadran con los gastos reales.
  void _maybeReconcile(ExpenseProject p, List<Expense> items) {
    final sum = items.fold<int>(0, (a, e) => a + e.amountCents);
    final sig =
        '${items.length}|$sum|${p.totalCents}|${p.expenseCount}|'
        '${p.totalsByUid.length}';
    if (sig == _lastReconcile) return;
    _lastReconcile = sig;
    _repo.reconcileTotals(p, items);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // ACCIONES
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> _openExpenseSheet(ExpenseProject p, {Expense? existing}) async {
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ExpenseSheet(
        project: p,
        people: _people,
        existing: existing,
        canDelete:
            existing != null &&
            (existing.createdBy == _myUid || p.isOwner(_myUid)),
      ),
    );
    if (result == 'added') _snack('Gasto añadido');
    if (result == 'updated') _snack('Gasto actualizado');
    if (result == 'deleted') _snack('Gasto eliminado');
  }

  bool _canEditExpense(ExpenseProject p, Expense e) =>
      e.createdBy == _myUid || p.isOwner(_myUid);

  Future<bool> _confirm(
    String title,
    String body, {
    String ok = 'Aceptar',
    bool danger = false,
  }) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              ok,
              style: TextStyle(
                color: danger ? ExpenseColors.negative : ExpenseColors.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
    return r == true;
  }

  Future<void> _onMenu(String action, ExpenseProject p) async {
    switch (action) {
      case 'edit':
        await Navigator.of(context).push<String>(
          MaterialPageRoute(
            builder: (_) => ExpenseProjectFormScreen(project: p),
          ),
        );
        if (p.seriesId.isNotEmpty) {
          _seriesRequested = false;
          _ensureSeriesLoaded(p);
        }
        break;

      case 'stop':
        if (await _confirm(
          'Detener periodicidad',
          'No se crearán más periodos de "${p.title}". '
              'Los que ya existen se conservan.',
          ok: 'Detener',
          danger: true,
        )) {
          await _repo.stopSeries(p.seriesId);
          if (mounted) setState(() => _seriesActive = false);
          _snack('Periodicidad detenida');
        }
        break;

      case 'leave':
        if (await _confirm(
          'Salir del proyecto',
          'Dejarás de ver "${p.title}"'
              '${p.isRecurring ? ' y sus próximos periodos' : ''}. '
              'Tus gastos se mantienen en el proyecto.',
          ok: 'Salir',
          danger: true,
        )) {
          _closing = true;
          await _repo.leaveProject(p);
          if (mounted) Navigator.of(context).pop();
        }
        break;

      case 'delete':
        await _confirmDelete(p);
        break;
    }
  }

  Future<void> _confirmDelete(ExpenseProject p) async {
    var stopToo = p.isRecurring && _seriesActive == true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Eliminar proyecto'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Se borrarán "${p.title}" y sus ${p.expenseCount} gastos '
                'para todos los miembros.',
              ),
              if (p.isRecurring && _seriesActive == true) ...[
                const SizedBox(height: 8),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: stopToo,
                  activeColor: ExpenseColors.primary,
                  onChanged: (v) => setS(() => stopToo = v ?? false),
                  title: const Text('Detener también los próximos periodos'),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text(
                'Eliminar',
                style: TextStyle(
                  color: ExpenseColors.negative,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    _closing = true;
    try {
      await _repo.deleteProject(p, alsoStopSeries: stopToo);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      _closing = false;
      _snack('No se pudo eliminar: $e', error: true);
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<ExpenseProject?>(
      stream: _projectStream,
      initialData: widget.initial,
      builder: (context, ps) {
        if (_closing) return _message('');
        if (ps.hasError) {
          return _message('No tienes acceso a este proyecto');
        }
        final p = ps.data;
        if (p == null) {
          if (ps.connectionState == ConnectionState.waiting) {
            return _message(null);
          }
          return _message('Este proyecto ya no existe');
        }
        if (!p.members.contains(_myUid)) {
          return _message('Ya no formas parte de este proyecto');
        }
        _ensureSeriesLoaded(p);

        return StreamBuilder<ExpenseListSnapshot>(
          stream: _expensesStream,
          builder: (context, es) {
            final all = es.data?.items ?? const <Expense>[];
            if (es.data?.fromServer == true) _maybeReconcile(p, all);
            final visible = all
                .where((e) => !_hiddenIds.contains(e.id))
                .toList();
            final loading = !es.hasData && !es.hasError;
            return _buildScaffold(p, visible, loading, es.error);
          },
        );
      },
    );
  }

  /// Pantalla simple para cargando (text == null) o avisos.
  Widget _message(String? text) {
    return Scaffold(
      backgroundColor: ExpenseColors.background,
      appBar: AppBar(
        backgroundColor: ExpenseColors.primary,
        foregroundColor: Colors.white,
        title: const Text('Gastos'),
      ),
      body: text == null
          ? const Center(child: CircularProgressIndicator())
          : (text.isEmpty
                ? const SizedBox.shrink()
                : Center(
                    child: ExpenseEmptyState(
                      icon: Icons.lock_outline,
                      title: text,
                    ),
                  )),
    );
  }

  Widget _buildScaffold(
    ExpenseProject p,
    List<Expense> expenses,
    bool loading,
    Object? error,
  ) {
    final isOwner = p.isOwner(_myUid);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: ExpenseColors.background,
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: ExpenseColors.primary,
          foregroundColor: Colors.white,
          onPressed: () => _openExpenseSheet(p),
          icon: const Icon(Icons.add),
          label: const Text('Añadir gasto'),
        ),
        body: NestedScrollView(
          headerSliverBuilder: (ctx, innerScrolled) => [
            SliverOverlapAbsorber(
              handle: NestedScrollView.sliverOverlapAbsorberHandleFor(ctx),
              sliver: SliverAppBar(
                pinned: true,
                expandedHeight: 300,
                forceElevated: innerScrolled,
                backgroundColor: ExpenseColors.primary,
                foregroundColor: Colors.white,
                title: Text(
                  p.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                actions: [
                  IconButton(
                    tooltip: _newestFirst
                        ? 'Más antiguos primero'
                        : 'Más recientes primero',
                    icon: Icon(
                      _newestFirst
                          ? Icons.arrow_downward_rounded
                          : Icons.arrow_upward_rounded,
                    ),
                    onPressed: () =>
                        setState(() => _newestFirst = !_newestFirst),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (a) => _onMenu(a, p),
                    itemBuilder: (_) => [
                      if (isOwner)
                        const PopupMenuItem(
                          value: 'edit',
                          child: ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.edit_outlined),
                            title: Text('Editar / compartir'),
                          ),
                        ),
                      if (isOwner && p.isRecurring && _seriesActive == true)
                        const PopupMenuItem(
                          value: 'stop',
                          child: ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.stop_circle_outlined),
                            title: Text('Detener periodicidad'),
                          ),
                        ),
                      if (!isOwner)
                        const PopupMenuItem(
                          value: 'leave',
                          child: ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.logout),
                            title: Text('Salir del proyecto'),
                          ),
                        ),
                      if (isOwner)
                        const PopupMenuItem(
                          value: 'delete',
                          child: ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                              Icons.delete_outline,
                              color: ExpenseColors.negative,
                            ),
                            title: Text(
                              'Eliminar proyecto',
                              style: TextStyle(color: ExpenseColors.negative),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  collapseMode: CollapseMode.pin,
                  background: _DetailHeader(
                    project: p,
                    people: _people,
                    seriesStopped: p.isRecurring && _seriesActive == false,
                  ),
                ),
                bottom: TabBar(
                  indicatorColor: Colors.white,
                  indicatorWeight: 3,
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white70,
                  dividerColor: Colors.transparent,
                  labelStyle: const TextStyle(fontWeight: FontWeight.w700),
                  tabs: [
                    Tab(text: 'Gastos (${expenses.length})'),
                    const Tab(text: 'Totales'),
                  ],
                ),
              ),
            ),
          ],
          body: TabBarView(
            children: [
              _TabBody(
                storageKey: 'gastos_${p.id}',
                children: _buildExpenseList(p, expenses, loading, error),
              ),
              _TabBody(
                storageKey: 'totales_${p.id}',
                children: _buildTotals(p, expenses),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // PESTAÑA GASTOS
  // ══════════════════════════════════════════════════════════════════════════

  List<Widget> _buildExpenseList(
    ExpenseProject p,
    List<Expense> expenses,
    bool loading,
    Object? error,
  ) {
    if (error != null) {
      return [
        ExpenseEmptyState(
          icon: Icons.cloud_off,
          title: 'No se pudieron cargar los gastos',
          subtitle: '$error',
        ),
      ];
    }
    if (loading) {
      return const [
        Padding(
          padding: EdgeInsets.all(40),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    if (expenses.isEmpty) {
      return const [
        ExpenseEmptyState(
          icon: Icons.receipt_long_outlined,
          title: 'Aún no hay gastos',
          subtitle: 'Pulsa "Añadir gasto" para apuntar el primero.',
        ),
      ];
    }

    final byDay = <int, List<Expense>>{};
    for (final e in expenses) {
      byDay.putIfAbsent(e.date.millisecondsSinceEpoch, () => []).add(e);
    }
    final days = byDay.keys.toList()..sort();
    final ordered = _newestFirst ? days.reversed.toList() : days;

    final out = <Widget>[];
    for (final ms in ordered) {
      final list = byDay[ms]!
        ..sort((a, b) => b.amountCents.compareTo(a.amountCents));
      final dayTotal = list.fold<int>(0, (a, e) => a + e.amountCents);
      final day = DateTime.fromMillisecondsSinceEpoch(ms);

      out.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 10, 4, 8),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: isSameDay(day, DateTime.now())
                      ? ExpenseColors.primary
                      : Colors.grey.shade400,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  fmtDayHeader(day),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: ExpenseColors.primaryDark,
                  ),
                ),
              ),
              Text(
                formatEuros(dayTotal),
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      );

      for (final e in list) {
        final canEdit = _canEditExpense(p, e);
        final tile = _ExpenseTile(
          expense: e,
          project: p,
          people: _people,
          onTap: () {
            if (canEdit) {
              _openExpenseSheet(p, existing: e);
            } else {
              _snack(
                'Solo quien lo añadió o el creador del proyecto puede '
                'modificarlo',
              );
            }
          },
        );
        if (!canEdit) {
          out.add(tile);
          continue;
        }
        out.add(
          Dismissible(
            key: ValueKey('exp_${e.id}'),
            direction: DismissDirection.endToStart,
            background: Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.only(right: 20),
              alignment: Alignment.centerRight,
              decoration: BoxDecoration(
                color: ExpenseColors.negative,
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(Icons.delete_outline, color: Colors.white),
            ),
            confirmDismiss: (_) => _confirm(
              'Eliminar gasto',
              '¿Eliminar "${e.concept}" (${formatEuros(e.amountCents)})?',
              ok: 'Eliminar',
              danger: true,
            ),
            onDismissed: (_) async {
              setState(() => _hiddenIds.add(e.id));
              try {
                await _repo.deleteExpense(project: p, expense: e);
                _snack('Gasto eliminado');
              } catch (err) {
                if (mounted) setState(() => _hiddenIds.remove(e.id));
                _snack('No se pudo eliminar: $err', error: true);
              }
            },
            child: tile,
          ),
        );
      }
    }
    return out;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // PESTAÑA TOTALES
  // ══════════════════════════════════════════════════════════════════════════

  List<Widget> _buildTotals(ExpenseProject p, List<Expense> expenses) {
    final status = p.statusAt(DateTime.now());
    final finished = status == ExpenseProjectStatus.finished;
    final isSum = p.type == ExpenseProjectType.sum;

    final total = expenses.fold<int>(0, (a, e) => a + e.amountCents);
    final paid = <String, int>{};
    final counts = <String, int>{};
    for (final e in expenses) {
      paid[e.paidByUid] = (paid[e.paidByUid] ?? 0) + e.amountCents;
      counts[e.paidByUid] = (counts[e.paidByUid] ?? 0) + 1;
    }
    // Participantes: miembros actuales + quien pagó algo aunque ya no esté.
    final participants = <String>{...p.members, ...paid.keys}.toList()
      ..sort((a, b) => (paid[b] ?? 0).compareTo(paid[a] ?? 0));
    final n = math.max(1, participants.length);

    final out = <Widget>[];

    // ── Aviso de estado ──────────────────────────────────────────────────────
    out.add(
      Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: finished
              ? ExpenseColors.positive.withOpacity(0.08)
              : ExpenseColors.primary.withOpacity(0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: finished
                ? ExpenseColors.positive.withOpacity(0.3)
                : ExpenseColors.primary.withOpacity(0.18),
          ),
        ),
        child: Row(
          children: [
            Icon(
              finished ? Icons.flag_rounded : Icons.hourglass_bottom_rounded,
              color: finished ? ExpenseColors.positive : ExpenseColors.primary,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                finished
                    ? 'Proyecto finalizado el ${fmtDate(p.endDate)}. '
                          'Estos son los totales definitivos.'
                    : 'Totales provisionales: el proyecto termina el '
                          '${fmtDate(p.endDate)}.',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: finished
                      ? ExpenseColors.positive
                      : ExpenseColors.primaryDark,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    // ── Cifras principales ───────────────────────────────────────────────────
    if (isSum) {
      out.add(
        Row(
          children: [
            Expanded(
              child: _StatTile(
                label: 'Total',
                value: formatEuros(total),
                icon: Icons.summarize_outlined,
                color: ExpenseColors.sum,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _StatTile(
                label: 'Gastos',
                value: '${expenses.length}',
                icon: Icons.receipt_outlined,
                color: ExpenseColors.primary,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _StatTile(
                label: 'Por persona',
                value: formatEuros(total ~/ n),
                icon: Icons.person_outline,
                color: ExpenseColors.accent,
              ),
            ),
          ],
        ),
      );
    } else {
      final remaining = p.budgetCents - total;
      out.add(
        Row(
          children: [
            Expanded(
              child: _StatTile(
                label: 'Presupuesto',
                value: formatEuros(p.budgetCents),
                icon: Icons.account_balance_wallet_outlined,
                color: ExpenseColors.primary,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _StatTile(
                label: 'Gastado',
                value: formatEuros(total),
                icon: Icons.shopping_bag_outlined,
                color: ExpenseColors.subtract,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _StatTile(
                label: remaining < 0 ? 'Excedido' : 'Queda',
                value: formatEuros(remaining.abs()),
                icon: remaining < 0
                    ? Icons.warning_amber_rounded
                    : Icons.savings_outlined,
                color: remaining < 0
                    ? ExpenseColors.negative
                    : ExpenseColors.positive,
              ),
            ),
          ],
        ),
      );
    }

    // ── Lo que ha puesto cada uno ────────────────────────────────────────────
    out.add(
      _sectionTitle(
        isSum ? 'Lo que ha puesto cada uno' : 'Lo que ha gastado cada uno',
      ),
    );
    out.add(
      SoftCard(
        child: Column(
          children: [
            for (var i = 0; i < participants.length; i++) ...[
              if (i > 0) Divider(height: 18, color: Colors.grey.shade200),
              _PersonTotalRow(
                uid: participants[i],
                project: p,
                people: _people,
                amount: paid[participants[i]] ?? 0,
                count: counts[participants[i]] ?? 0,
                total: total,
              ),
            ],
          ],
        ),
      ),
    );

    // ── Cuentas (solo tipo Sumar y con más de una persona) ───────────────────
    if (isSum && participants.length > 1 && total > 0) {
      final sorted = [...participants]..sort();
      final base = total ~/ sorted.length;
      final rest = total % sorted.length;
      final balance = <String, int>{};
      for (var i = 0; i < sorted.length; i++) {
        final share = base + (i < rest ? 1 : 0);
        balance[sorted[i]] = (paid[sorted[i]] ?? 0) - share;
      }
      final transfers = _settle(balance);

      out.add(
        _sectionTitle(
          finished ? 'Cuentas finales' : 'Cuentas si se cerrara hoy',
        ),
      );
      out.add(
        SoftCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'A partes iguales: ${formatEuros(base)} por persona '
                '(${sorted.length} personas).',
                style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
              ),
              const SizedBox(height: 10),
              for (final uid in participants)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      PersonAvatar(
                        uid: uid,
                        people: _people,
                        project: p,
                        size: 26,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _people.name(uid, project: p),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      _BalanceText(cents: balance[uid] ?? 0),
                    ],
                  ),
                ),
              const Divider(height: 22),
              if (transfers.isEmpty)
                const Text(
                  'Todo cuadrado, nadie debe nada 🎉',
                  style: TextStyle(fontWeight: FontWeight.w600),
                )
              else ...[
                const Text(
                  'Para quedar en paz',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: ExpenseColors.primaryDark,
                  ),
                ),
                const SizedBox(height: 8),
                for (final t in transfers)
                  Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: ExpenseColors.background,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        PersonAvatar(
                          uid: t.from,
                          people: _people,
                          project: p,
                          size: 24,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            _people.name(t.from, project: p),
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 6),
                          child: Icon(
                            Icons.arrow_forward_rounded,
                            size: 16,
                            color: ExpenseColors.accent,
                          ),
                        ),
                        PersonAvatar(
                          uid: t.to,
                          people: _people,
                          project: p,
                          size: 24,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            _people.name(t.to, project: p),
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Spacer(),
                        Text(
                          formatEuros(t.cents),
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: ExpenseColors.primaryDark,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
      );
    }

    return out;
  }

  Widget _sectionTitle(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w800,
        color: ExpenseColors.primaryDark,
        letterSpacing: 0.2,
      ),
    ),
  );

  /// Reparte las deudas con el mínimo razonable de pagos (voraz: el que más
  /// debe paga al que más tiene que recibir).
  List<_Transfer> _settle(Map<String, int> balance) {
    final debtors = [
      for (final e in balance.entries)
        if (e.value < 0) _Bal(e.key, -e.value),
    ]..sort((a, b) => b.amount.compareTo(a.amount));
    final creditors = [
      for (final e in balance.entries)
        if (e.value > 0) _Bal(e.key, e.value),
    ]..sort((a, b) => b.amount.compareTo(a.amount));

    final out = <_Transfer>[];
    var i = 0;
    var j = 0;
    while (i < debtors.length && j < creditors.length) {
      final x = math.min(debtors[i].amount, creditors[j].amount);
      if (x > 0) out.add(_Transfer(debtors[i].uid, creditors[j].uid, x));
      debtors[i].amount -= x;
      creditors[j].amount -= x;
      if (debtors[i].amount == 0) i++;
      if (creditors[j].amount == 0) j++;
    }
    return out;
  }
}

class _Bal {
  final String uid;
  int amount;
  _Bal(this.uid, this.amount);
}

class _Transfer {
  final String from;
  final String to;
  final int cents;
  const _Transfer(this.from, this.to, this.cents);
}

// ════════════════════════════════════════════════════════════════════════════
// CABECERA
// ════════════════════════════════════════════════════════════════════════════

class _DetailHeader extends StatelessWidget {
  final ExpenseProject project;
  final ExpensePeople people;
  final bool seriesStopped;

  const _DetailHeader({
    required this.project,
    required this.people,
    required this.seriesStopped,
  });

  @override
  Widget build(BuildContext context) {
    final p = project;
    final isSubtract = p.type == ExpenseProjectType.subtract;
    final remaining = p.remainingCents;
    final over = isSubtract && remaining < 0;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [ExpenseColors.primaryDark, ExpenseColors.accent],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        MediaQuery.of(context).padding.top + kToolbarHeight + 4,
        20,
        48 + 14,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.event_outlined, size: 15, color: Colors.white70),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  fmtRange(p.startDate, p.endDate),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ),
            ],
          ),
          if (p.description.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              p.description,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white70, fontSize: 12.5),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              StatusChip(status: p.statusAt(DateTime.now()), onDark: true),
              InfoChip(
                icon: isSubtract
                    ? Icons.remove_circle_outline
                    : Icons.add_circle_outline,
                label: p.type.label,
                color: Colors.white,
                onDark: true,
              ),
              if (p.isRecurring)
                InfoChip(
                  icon: seriesStopped
                      ? Icons.pause_circle_outline
                      : Icons.autorenew,
                  label: seriesStopped
                      ? '${p.recurrence.label} · detenida'
                      : p.recurrence.label,
                  color: Colors.white,
                  onDark: true,
                ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isSubtract
                          ? (over ? 'Presupuesto excedido en' : 'Queda')
                          : 'Total gastado',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        formatEuros(
                          isSubtract ? remaining.abs() : p.totalCents,
                        ),
                        style: TextStyle(
                          color: over ? const Color(0xFFFFCDD2) : Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              AvatarStack(
                uids: p.members,
                people: people,
                project: p,
                size: 30,
              ),
            ],
          ),
          if (isSubtract) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: p.budgetUsedRatio,
                minHeight: 7,
                backgroundColor: Colors.white24,
                valueColor: AlwaysStoppedAnimation<Color>(
                  over ? const Color(0xFFFF8A80) : Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Gastado ${formatEuros(p.totalCents)} de ${formatEuros(p.budgetCents)}',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// PIEZAS DE LAS PESTAÑAS
// ════════════════════════════════════════════════════════════════════════════

/// Cuerpo desplazable de cada pestaña, integrado con la cabecera plegable.
class _TabBody extends StatelessWidget {
  final String storageKey;
  final List<Widget> children;

  const _TabBody({required this.storageKey, required this.children});

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      key: PageStorageKey<String>(storageKey),
      slivers: [
        SliverOverlapInjector(
          handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
          sliver: SliverList(delegate: SliverChildListDelegate(children)),
        ),
      ],
    );
  }
}

class _ExpenseTile extends StatelessWidget {
  final Expense expense;
  final ExpenseProject project;
  final ExpensePeople people;
  final VoidCallback onTap;

  const _ExpenseTile({
    required this.expense,
    required this.project,
    required this.people,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final e = expense;
    final payer = people.name(
      e.paidByUid,
      project: project,
      fallback: e.paidByName,
    );
    return SoftCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          PersonAvatar(
            uid: e.paidByUid,
            people: people,
            project: project,
            size: 38,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        e.concept,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (e.isInitial) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: ExpenseColors.accent.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'Inicial',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: ExpenseColors.accent,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  e.note.isEmpty ? 'Pagó $payer' : 'Pagó $payer · ${e.note}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            formatEuros(e.amountCents),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 17, color: color),
          ),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}

class _PersonTotalRow extends StatelessWidget {
  final String uid;
  final ExpenseProject project;
  final ExpensePeople people;
  final int amount;
  final int count;
  final int total;

  const _PersonTotalRow({
    required this.uid,
    required this.project,
    required this.people,
    required this.amount,
    required this.count,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    final ratio = total <= 0 ? 0.0 : amount / total;
    final color = ExpenseColors.forPerson(uid);
    final left = !project.members.contains(uid);
    return Column(
      children: [
        Row(
          children: [
            PersonAvatar(uid: uid, people: people, project: project, size: 34),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    people.name(uid, project: project),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    '$count ${count == 1 ? 'gasto' : 'gastos'}'
                    '${left ? ' · ya no está en el proyecto' : ''}',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  formatEuros(amount),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  '${(ratio * 100).toStringAsFixed(0)} %',
                  style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 6,
            backgroundColor: color.withOpacity(0.1),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }
}

class _BalanceText extends StatelessWidget {
  final int cents;
  const _BalanceText({required this.cents});

  @override
  Widget build(BuildContext context) {
    if (cents == 0) {
      return Text(
        'En paz',
        style: TextStyle(
          fontWeight: FontWeight.w700,
          color: Colors.grey.shade600,
        ),
      );
    }
    final positive = cents > 0;
    return Text(
      positive
          ? '+${formatEuros(cents)} le deben'
          : '${formatEuros(cents)} debe',
      style: TextStyle(
        fontWeight: FontWeight.w700,
        color: positive ? ExpenseColors.positive : ExpenseColors.negative,
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// HOJA AÑADIR / EDITAR GASTO
// ════════════════════════════════════════════════════════════════════════════

class _ExpenseSheet extends StatefulWidget {
  final ExpenseProject project;
  final ExpensePeople people;
  final Expense? existing;
  final bool canDelete;

  const _ExpenseSheet({
    required this.project,
    required this.people,
    this.existing,
    this.canDelete = false,
  });

  @override
  State<_ExpenseSheet> createState() => _ExpenseSheetState();
}

class _ExpenseSheetState extends State<_ExpenseSheet> {
  final _repo = ExpenseRepository.instance;
  final _amountCtrl = TextEditingController();
  final _conceptCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  late DateTime _date;
  late String _payer;
  bool _saving = false;
  String? _errorText;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    final p = widget.project;
    if (e != null) {
      _amountCtrl.text = formatEuros(e.amountCents, symbol: false);
      _conceptCtrl.text = e.concept;
      _noteCtrl.text = e.note;
      _date = e.date;
      _payer = e.paidByUid;
    } else {
      // Hoy, pero dentro de las fechas del proyecto.
      final today = startOfDay(DateTime.now());
      _date = today.isBefore(p.startDate)
          ? p.startDate
          : (today.isAfter(p.endDate) ? p.endDate : today);
      _payer = _repo.uid;
    }
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _conceptCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  List<String> get _payers {
    final list = [...widget.project.members];
    if (!list.contains(_payer)) list.add(_payer);
    list.sort((a, b) {
      if (a == _repo.uid) return -1;
      if (b == _repo.uid) return 1;
      return widget.people
          .name(a, project: widget.project)
          .compareTo(widget.people.name(b, project: widget.project));
    });
    return list;
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: 'Fecha del gasto',
    );
    if (picked != null) setState(() => _date = startOfDay(picked));
  }

  void _error(String msg) {
    // El SnackBar quedaría detrás de la hoja: el error se muestra dentro.
    setState(() => _errorText = msg);
  }

  Future<void> _save() async {
    final cents = parseEurosToCents(_amountCtrl.text);
    final concept = _conceptCtrl.text.trim();
    if (cents == null || cents <= 0) {
      _error('Indica un importe válido');
      return;
    }
    if (concept.isEmpty) {
      _error('Indica el concepto');
      return;
    }
    setState(() {
      _saving = true;
      _errorText = null;
    });
    try {
      if (_isEdit) {
        final before = widget.existing!;
        await _repo.updateExpense(
          project: widget.project,
          before: before,
          after: before.copyWith(
            concept: concept,
            amountCents: cents,
            date: _date,
            paidByUid: _payer,
            note: _noteCtrl.text.trim(),
          ),
        );
        if (mounted) Navigator.pop(context, 'updated');
      } else {
        await _repo.addExpense(
          project: widget.project,
          concept: concept,
          amountCents: cents,
          date: _date,
          paidByUid: _payer,
          note: _noteCtrl.text.trim(),
        );
        if (mounted) Navigator.pop(context, 'added');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        _error('No se pudo guardar: $e');
      }
    }
  }

  Future<void> _delete() async {
    final e = widget.existing;
    if (e == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar gasto'),
        content: Text(
          '¿Eliminar "${e.concept}" (${formatEuros(e.amountCents)})?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Eliminar',
              style: TextStyle(color: ExpenseColors.negative),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _saving = true);
    try {
      await _repo.deleteExpense(project: widget.project, expense: e);
      if (mounted) Navigator.pop(context, 'deleted');
    } catch (err) {
      if (mounted) {
        setState(() => _saving = false);
        _error('No se pudo eliminar: $err');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final p = widget.project;
    final outside = _date.isBefore(p.startDate) || _date.isAfter(p.endDate);

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  _isEdit ? 'Editar gasto' : 'Nuevo gasto',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _amountCtrl,
                  autofocus: !_isEdit,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                  ),
                  decoration: const InputDecoration(
                    hintText: '0,00',
                    suffixText: '€',
                    labelText: 'Importe',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _conceptCtrl,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Concepto',
                    hintText: 'Cena, gasolina, entradas…',
                    prefixIcon: Icon(Icons.label_outline),
                  ),
                ),
                const SizedBox(height: 12),
                InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: _pickDate,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade400),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.event, color: Colors.grey.shade600),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            fmtDayHeader(_date),
                            style: const TextStyle(fontSize: 15),
                          ),
                        ),
                        Icon(Icons.edit_calendar, color: Colors.grey.shade500),
                      ],
                    ),
                  ),
                ),
                if (outside)
                  Padding(
                    padding: const EdgeInsets.only(top: 6, left: 4),
                    child: Text(
                      'Fuera de las fechas del proyecto '
                      '(${fmtRange(p.startDate, p.endDate)})',
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: ExpenseColors.subtract,
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                const Text(
                  'Pagado por',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final uid in _payers)
                      ChoiceChip(
                        avatar: PersonAvatar(
                          uid: uid,
                          people: widget.people,
                          project: p,
                          size: 22,
                        ),
                        label: Text(widget.people.name(uid, project: p)),
                        selected: _payer == uid,
                        showCheckmark: false,
                        selectedColor: ExpenseColors.primary.withOpacity(0.14),
                        side: BorderSide(
                          color: _payer == uid
                              ? ExpenseColors.primary
                              : Colors.grey.shade300,
                        ),
                        labelStyle: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: _payer == uid
                              ? ExpenseColors.primaryDark
                              : Colors.grey.shade800,
                        ),
                        onSelected: (_) => setState(() => _payer = uid),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _noteCtrl,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Nota (opcional)',
                    prefixIcon: Icon(Icons.sticky_note_2_outlined),
                  ),
                ),
                const SizedBox(height: 18),
                if (_errorText != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.error_outline,
                          size: 18,
                          color: ExpenseColors.negative,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _errorText!,
                            style: const TextStyle(
                              color: ExpenseColors.negative,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                Row(
                  children: [
                    if (_isEdit && widget.canDelete) ...[
                      SizedBox(
                        height: 50,
                        child: OutlinedButton(
                          onPressed: _saving ? null : _delete,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: ExpenseColors.negative,
                            side: const BorderSide(
                              color: ExpenseColors.negative,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: const Icon(Icons.delete_outline),
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      child: SizedBox(
                        height: 50,
                        child: FilledButton(
                          onPressed: _saving ? null : _save,
                          style: FilledButton.styleFrom(
                            backgroundColor: ExpenseColors.primary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: _saving
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
                                  _isEdit ? 'Guardar cambios' : 'Añadir gasto',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
