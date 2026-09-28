// lib/views/expenses/expense_project_form_screen.dart
//
// Crear / editar un proyecto de gastos:
//   · Nombre y descripción
//   · Tipo: Sumar gastos | Restar de un total (presupuesto)
//   · Fechas del proyecto (p. ej. las del viaje; se puede crear con antelación)
//   · Periodicidad: una vez, cada semana, cada 15 días, cada mes, cada año
//   · Compartir con amigos
//   · Gastos iniciales (solo al crear; en los periódicos se repiten en cada
//     periodo)
//
// Al crear devuelve (pop) el id del proyecto nuevo.

import 'package:flutter/material.dart';
import '../../core/expense_repository.dart';
import '../../core/week_dates.dart';
import '../../models/expense_models.dart';
import '../../models/friend_model.dart';
import 'expense_widgets.dart';

class ExpenseProjectFormScreen extends StatefulWidget {
  /// null = crear; si no, editar este proyecto.
  final ExpenseProject? project;

  const ExpenseProjectFormScreen({super.key, this.project});

  @override
  State<ExpenseProjectFormScreen> createState() =>
      _ExpenseProjectFormScreenState();
}

class _InitialRow {
  final TextEditingController concept = TextEditingController();
  final TextEditingController amount = TextEditingController();

  void dispose() {
    concept.dispose();
    amount.dispose();
  }
}

class _ExpenseProjectFormScreenState extends State<ExpenseProjectFormScreen> {
  final _repo = ExpenseRepository.instance;

  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _budgetCtrl = TextEditingController();
  final List<_InitialRow> _initialRows = [];

  ExpenseProjectType _type = ExpenseProjectType.sum;
  ExpenseRecurrence _recurrence = ExpenseRecurrence.once;
  late DateTime _start;
  late DateTime _end;

  late ExpensePeople _people = ExpensePeople(myUid: _repo.uid);
  final Set<String> _selectedUids = {};
  bool _loadingFriends = true;

  bool _applyToSeries = true;
  bool? _seriesActive; // null = cargando / no es periódico
  bool _saving = false;

  bool get _isEdit => widget.project != null;

  @override
  void initState() {
    super.initState();
    final p = widget.project;
    final today = startOfDay(DateTime.now());
    if (p != null) {
      _titleCtrl.text = p.title;
      _descCtrl.text = p.description;
      _type = p.type;
      _recurrence = p.recurrence;
      _start = p.startDate;
      _end = p.endDate;
      if (p.budgetCents > 0) {
        _budgetCtrl.text = formatEuros(p.budgetCents, symbol: false);
      }
      _selectedUids.addAll(p.members.where((u) => u != p.ownerId));
      if (p.seriesId.isNotEmpty) {
        _repo.getSeries(p.seriesId).then((s) {
          if (mounted) setState(() => _seriesActive = s?.active ?? false);
        });
      }
    } else {
      _start = today;
      _end = today;
      _initialRows.add(_InitialRow());
    }
    ExpensePeople.load(_repo.uid).then((pp) {
      if (!mounted) return;
      setState(() {
        _people = pp;
        _loadingFriends = false;
      });
    });
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _budgetCtrl.dispose();
    for (final r in _initialRows) {
      r.dispose();
    }
    super.dispose();
  }

  // ══════════════════════════════════════════════════════════════════════════
  // FECHAS
  // ══════════════════════════════════════════════════════════════════════════

  /// Fin por defecto de un periodo que empieza en [start]: el día antes del
  /// siguiente periodo (mensual → hasta fin de mes, semanal → 7 días…).
  DateTime _defaultEndFor(DateTime start, ExpenseRecurrence r) {
    if (!r.isRecurring) return start;
    return addDays(occurrenceStart(start, r, 1), -1);
  }

  void _setRecurrence(ExpenseRecurrence r) {
    setState(() {
      _recurrence = r;
      if (r.isRecurring) _end = _defaultEndFor(_start, r);
    });
  }

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDateRange: DateTimeRange(start: _start, end: _end),
      helpText: 'Fechas del proyecto',
      saveText: 'Aceptar',
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: Theme.of(
            ctx,
          ).colorScheme.copyWith(primary: ExpenseColors.primary),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() {
      _start = startOfDay(picked.start);
      _end = startOfDay(picked.end);
    });
  }

  Future<void> _pickStartOnly() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _start,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: 'Inicio del primer periodo',
    );
    if (picked == null) return;
    setState(() {
      _start = startOfDay(picked);
      _end = _defaultEndFor(_start, _recurrence);
    });
  }

  /// Atajos para dejar el periodo "redondo".
  List<(String, VoidCallback)> _presets() {
    switch (_recurrence) {
      case ExpenseRecurrence.monthly:
        return [
          (
            'Este mes completo',
            () => setState(() {
              final now = DateTime.now();
              _start = DateTime(now.year, now.month, 1);
              _end = DateTime(now.year, now.month + 1, 0);
            }),
          ),
          (
            'Desde el mes que viene',
            () => setState(() {
              final now = DateTime.now();
              _start = DateTime(now.year, now.month + 1, 1);
              _end = DateTime(now.year, now.month + 2, 0);
            }),
          ),
        ];
      case ExpenseRecurrence.weekly:
        return [
          (
            'De lunes a domingo',
            () => setState(() {
              _start = mondayOf(_start);
              _end = addDays(_start, 6);
            }),
          ),
        ];
      case ExpenseRecurrence.yearly:
        return [
          (
            'Año natural',
            () => setState(() {
              _start = DateTime(_start.year, 1, 1);
              _end = DateTime(_start.year, 12, 31);
            }),
          ),
        ];
      case ExpenseRecurrence.biweekly:
      case ExpenseRecurrence.once:
        return const [];
    }
  }

  String _periodHint() {
    if (!_recurrence.isRecurring) {
      return 'Por ejemplo, las fechas del viaje. Puedes crearlo con antelación.';
    }
    final next = occurrenceStart(_start, _recurrence, 1);
    final full = isSameDay(_end, addDays(next, -1));
    final days = daysBetween(_start, _end) + 1;
    final len = full
        ? 'cada periodo ocupa ${_recurrence == ExpenseRecurrence.monthly ? 'el mes completo' : 'todo el intervalo'}'
        : 'cada periodo dura $days ${days == 1 ? 'día' : 'días'}';
    return 'El siguiente se creará solo el ${fmtDate(next)} ($len). '
        'Si nadie abre la app ese día, se crea en cuanto entre cualquiera.';
  }

  // ══════════════════════════════════════════════════════════════════════════
  // GUARDAR
  // ══════════════════════════════════════════════════════════════════════════

  void _snack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? ExpenseColors.negative : null,
      ),
    );
  }

  Future<void> _save() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      _snack('Ponle un nombre al proyecto', error: true);
      return;
    }
    if (_end.isBefore(_start)) {
      _snack('La fecha de fin no puede ser anterior al inicio', error: true);
      return;
    }

    var budget = 0;
    if (_type == ExpenseProjectType.subtract) {
      final b = parseEurosToCents(_budgetCtrl.text);
      if (b == null || b <= 0) {
        _snack('Indica el total disponible', error: true);
        return;
      }
      budget = b;
    }

    final initial = <InitialExpense>[];
    if (!_isEdit) {
      for (final r in _initialRows) {
        final c = r.concept.text.trim();
        final a = r.amount.text.trim();
        if (c.isEmpty && a.isEmpty) continue;
        final cents = parseEurosToCents(a);
        if (c.isEmpty || cents == null || cents <= 0) {
          _snack(
            'Revisa los gastos iniciales: concepto e importe',
            error: true,
          );
          return;
        }
        initial.add(InitialExpense(concept: c, amountCents: cents));
      }
    }

    final friends = _people.friends
        .where((f) => f.firebaseUid != null)
        .where((f) => _selectedUids.contains(f.firebaseUid))
        .toList();

    // Al editar, conservo a los miembros que no son amigos míos (los añadió
    // otra persona) para no echarlos sin querer.
    if (_isEdit) {
      final p = widget.project!;
      for (final uid in _selectedUids) {
        if (friends.any((f) => f.firebaseUid == uid)) continue;
        friends.add(
          FriendModel(
            name: p.memberNames[uid] ?? '',
            email: '',
            firebaseUid: uid,
          ),
        );
      }
    }

    setState(() => _saving = true);
    try {
      if (_isEdit) {
        await _repo.updateProject(
          project: widget.project!,
          title: title,
          description: _descCtrl.text.trim(),
          type: _type,
          budgetCents: budget,
          start: _start,
          end: _end,
          sharedWith: friends,
          applyToSeries: _applyToSeries,
        );
        if (mounted) Navigator.of(context).pop(widget.project!.id);
      } else {
        final id = await _repo.createProject(
          title: title,
          description: _descCtrl.text.trim(),
          type: _type,
          budgetCents: budget,
          start: _start,
          end: _end,
          recurrence: _recurrence,
          sharedWith: friends,
          initialExpenses: initial,
        );
        if (mounted) Navigator.of(context).pop(id);
      }
    } catch (e) {
      if (mounted) _snack('No se pudo guardar: $e', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _stopSeries() async {
    final p = widget.project;
    if (p == null || p.seriesId.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Detener periodicidad'),
        content: const Text(
          'No se crearán más periodos de este proyecto. '
          'Los que ya existen se conservan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Detener',
              style: TextStyle(color: ExpenseColors.negative),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _repo.stopSeries(p.seriesId);
    if (mounted) setState(() => _seriesActive = false);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ExpenseColors.background,
      appBar: AppBar(
        backgroundColor: ExpenseColors.primary,
        foregroundColor: Colors.white,
        title: Text(_isEdit ? 'Editar proyecto' : 'Nuevo proyecto de gastos'),
        actions: [
          IconButton(
            tooltip: 'Guardar',
            icon: const Icon(Icons.check),
            onPressed: _saving ? null : _save,
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            _section(
              icon: Icons.edit_note,
              title: 'Proyecto',
              child: Column(
                children: [
                  TextField(
                    controller: _titleCtrl,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Nombre *',
                      hintText: 'Viaje a Lisboa, Casa octubre…',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _descCtrl,
                    textCapitalization: TextCapitalization.sentences,
                    minLines: 1,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Descripción (opcional)',
                    ),
                  ),
                ],
              ),
            ),
            _section(
              icon: Icons.tune,
              title: 'Tipo',
              child: Column(
                children: [
                  _TypeOption(
                    selected: _type == ExpenseProjectType.sum,
                    color: ExpenseColors.sum,
                    icon: ExpenseColors.iconForType(ExpenseProjectType.sum),
                    title: 'Sumar gastos',
                    subtitle:
                        'Cada uno va añadiendo lo que paga. Al final todos ven '
                        'cuánto ha puesto cada uno.',
                    onTap: () => setState(() => _type = ExpenseProjectType.sum),
                  ),
                  const SizedBox(height: 8),
                  _TypeOption(
                    selected: _type == ExpenseProjectType.subtract,
                    color: ExpenseColors.subtract,
                    icon: ExpenseColors.iconForType(
                      ExpenseProjectType.subtract,
                    ),
                    title: 'Restar de un total',
                    subtitle:
                        'Fijas un presupuesto y cada gasto lo va restando.',
                    onTap: () =>
                        setState(() => _type = ExpenseProjectType.subtract),
                  ),
                  if (_type == ExpenseProjectType.subtract) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _budgetCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Total disponible *',
                        suffixText: '€',
                        prefixIcon: Icon(Icons.account_balance_wallet_outlined),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            _section(
              icon: Icons.autorenew,
              title: 'Periodicidad',
              child: _isEdit ? _buildRecurrenceReadOnly() : _buildRecurrence(),
            ),
            _section(
              icon: Icons.date_range,
              title: _recurrence.isRecurring
                  ? 'Primer periodo'
                  : 'Fechas del proyecto',
              child: _buildDates(),
            ),
            _section(
              icon: Icons.group_outlined,
              title: 'Compartir con',
              child: _buildFriends(),
            ),
            if (!_isEdit)
              _section(
                icon: Icons.receipt_long_outlined,
                title: 'Gastos iniciales',
                child: _buildInitialExpenses(),
              ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: ExpenseColors.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.check),
                label: Text(_isEdit ? 'Guardar cambios' : 'Crear proyecto'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section({
    required IconData icon,
    required String title,
    required Widget child,
  }) {
    return SoftCard(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: ExpenseColors.primary),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: ExpenseColors.primaryDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _buildRecurrence() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: ExpenseRecurrence.values.map((r) {
        final sel = _recurrence == r;
        return ChoiceChip(
          label: Text(r.label),
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
          ),
          onSelected: (_) => _setRecurrence(r),
        );
      }).toList(),
    );
  }

  Widget _buildRecurrenceReadOnly() {
    final p = widget.project!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            InfoChip(
              icon: p.isRecurring ? Icons.autorenew : Icons.looks_one_outlined,
              label: p.recurrence.label,
              color: ExpenseColors.primary,
            ),
            const SizedBox(width: 8),
            if (p.isRecurring && _seriesActive == false)
              InfoChip(
                icon: Icons.pause_circle_outline,
                label: 'Detenida',
                color: Colors.grey.shade700,
              ),
            const Spacer(),
            if (p.isRecurring && _seriesActive == true)
              TextButton.icon(
                onPressed: _stopSeries,
                icon: const Icon(Icons.stop_circle_outlined, size: 18),
                label: const Text('Detener'),
                style: TextButton.styleFrom(
                  foregroundColor: ExpenseColors.negative,
                ),
              ),
          ],
        ),
        if (p.isRecurring) ...[
          const SizedBox(height: 4),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            activeColor: ExpenseColors.primary,
            value: _applyToSeries,
            onChanged: (v) => setState(() => _applyToSeries = v),
            title: const Text('Aplicar también a los próximos periodos'),
            subtitle: const Text(
              'Nombre, tipo, total y personas con las que se comparte.',
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildDates() {
    final days = daysBetween(_start, _end) + 1;
    final presets = _isEdit ? const <(String, VoidCallback)>[] : _presets();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: _pickRange,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Row(
              children: [
                Expanded(child: _dateBox('Inicio', _start)),
                Icon(Icons.arrow_forward, color: Colors.grey.shade400),
                Expanded(child: _dateBox('Fin', _end, alignEnd: true)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Text(
              '$days ${days == 1 ? 'día' : 'días'}',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const Spacer(),
            if (_recurrence.isRecurring && !_isEdit)
              TextButton(
                onPressed: _pickStartOnly,
                child: const Text('Cambiar solo el inicio'),
              ),
          ],
        ),
        if (presets.isNotEmpty) ...[
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final pr in presets)
                ActionChip(
                  avatar: const Icon(
                    Icons.auto_fix_high,
                    size: 16,
                    color: ExpenseColors.primary,
                  ),
                  label: Text(pr.$1),
                  onPressed: pr.$2,
                ),
            ],
          ),
        ],
        const SizedBox(height: 8),
        Text(
          _isEdit && widget.project!.isRecurring
              ? 'Cambiar estas fechas solo afecta a este periodo.'
              : _periodHint(),
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
      ],
    );
  }

  Widget _dateBox(String label, DateTime d, {bool alignEnd = false}) {
    return Column(
      crossAxisAlignment: alignEnd
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
        ),
        const SizedBox(height: 2),
        Text(
          fmtDate(d),
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }

  Widget _buildFriends() {
    if (_loadingFriends) {
      return const Padding(
        padding: EdgeInsets.all(8),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final friends = _people.friends
        .where((f) => f.firebaseUid != null && f.firebaseUid!.isNotEmpty)
        .toList();

    // Miembros actuales que no están en mi lista de amigos (al editar).
    final others = _isEdit
        ? widget.project!.members
              .where(
                (u) =>
                    u != widget.project!.ownerId &&
                    u != _repo.uid &&
                    !friends.any((f) => f.firebaseUid == u),
              )
              .toList()
        : const <String>[];

    if (friends.isEmpty && others.isEmpty) {
      return Text(
        'Aún no tienes amigos. Añádelos desde "Amigos" para poder compartir.',
        style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
      );
    }

    final canEditMembers = !_isEdit || widget.project!.isOwner(_repo.uid);

    Widget chip(String uid, String label, String? emoji) {
      final sel = _selectedUids.contains(uid);
      return FilterChip(
        avatar: Text(emoji ?? '👤', style: const TextStyle(fontSize: 16)),
        label: Text(label),
        selected: sel,
        showCheckmark: true,
        checkmarkColor: Colors.white,
        selectedColor: ExpenseColors.accent,
        backgroundColor: Colors.white,
        side: BorderSide(
          color: sel ? ExpenseColors.accent : Colors.grey.shade300,
        ),
        labelStyle: TextStyle(
          color: sel ? Colors.white : Colors.grey.shade800,
          fontWeight: FontWeight.w600,
        ),
        onSelected: !canEditMembers
            ? null
            : (v) => setState(() {
                if (v) {
                  _selectedUids.add(uid);
                } else {
                  _selectedUids.remove(uid);
                }
              }),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final f in friends)
              chip(f.firebaseUid!, f.displayName, f.logo),
            for (final u in others)
              chip(u, widget.project!.memberNames[u] ?? 'Miembro', null),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          _selectedUids.isEmpty
              ? 'Solo tú verás este proyecto.'
              : 'Todos podrán añadir gastos y ver los totales.',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
      ],
    );
  }

  Widget _buildInitialExpenses() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _recurrence.isRecurring
              ? 'Se añadirán automáticamente en cada periodo (alquiler, '
                    'cuotas, suscripciones…). Constan como pagados por ti.'
              : 'Gastos que ya conoces (reservas, billetes…). Constan como '
                    'pagados por ti; luego puedes cambiar quién pagó.',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 10),
        for (var i = 0; i < _initialRows.length; i++)
          Padding(
            key: ObjectKey(_initialRows[i]),
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _initialRows[i].concept,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Concepto',
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _initialRows[i].amount,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Importe',
                      suffixText: '€',
                      isDense: true,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Quitar',
                  icon: Icon(Icons.close, color: Colors.grey.shade500),
                  onPressed: () {
                    final row = _initialRows[i];
                    setState(() => _initialRows.remove(row));
                    // Se libera cuando su TextField ya no está en pantalla.
                    WidgetsBinding.instance.addPostFrameCallback(
                      (_) => row.dispose(),
                    );
                  },
                ),
              ],
            ),
          ),
        TextButton.icon(
          onPressed: () => setState(() => _initialRows.add(_InitialRow())),
          icon: const Icon(Icons.add),
          label: const Text('Añadir gasto inicial'),
          style: TextButton.styleFrom(foregroundColor: ExpenseColors.primary),
        ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// OPCIÓN DE TIPO
// ════════════════════════════════════════════════════════════════════════════

class _TypeOption extends StatelessWidget {
  final bool selected;
  final Color color;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _TypeOption({
    required this.selected,
    required this.color,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.08) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? color : Colors.grey.shade300,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: selected ? color : color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: selected ? Colors.white : color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: selected ? color : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected ? color : Colors.grey.shade400,
            ),
          ],
        ),
      ),
    );
  }
}
