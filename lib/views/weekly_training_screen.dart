// lib/views/weekly_training_screen.dart

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/weekly_training_model.dart';
import '../core/weekly_training_repository.dart';
import '../core/date_change_service.dart';
import 'share_weekly_dialog.dart';
import 'date_change_prompt.dart';
import 'week_day_picker.dart';
import '../core/week_dates.dart';
import '../core/weekly_share_service.dart';
import '../core/recurrence_rule.dart';
import 'recurrence_picker.dart';
import 'image_helpers.dart';

// ── Helpers de fecha en español sin dependencia de locale ────────────────────
const _diasSemana = [
  'Lunes',
  'Martes',
  'Miércoles',
  'Jueves',
  'Viernes',
  'Sábado',
  'Domingo',
];
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
const _diasCortos = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];

String _fmtShort(DateTime d) => '${d.day} ${_meses[d.month]}';
String _fmtMedium(DateTime d) => '${_diasCortos[d.weekday - 1]} ${d.day}';
String _fmtWeekRange(DateTime monday) {
  final sunday = addDays(monday, 6);
  return '${_fmtShort(monday)} – ${_fmtShort(sunday)}';
}

class WeeklyTrainingScreen extends StatefulWidget {
  const WeeklyTrainingScreen({Key? key}) : super(key: key);

  @override
  State<WeeklyTrainingScreen> createState() => _WeeklyTrainingScreenState();
}

class _WeeklyTrainingScreenState extends State<WeeklyTrainingScreen> {
  final _repo = WeeklyTrainingRepository.instance;

  late DateTime _currentWeekStart;
  List<WeeklyTrainingEntry> _entries = [];
  bool _isLoading = true;
  String _myUid = '';

  // Portapapeles para copiar/pegar semanas
  List<WeeklyTrainingEntry>? _clipboard;
  DateTime? _clipboardSourceMonday;

  static const Color _primary = Color(0xFFEF6C00); // naranja 800
  static const Color _accent = Color(0xFFFF9800);

  @override
  void initState() {
    super.initState();
    _myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    _currentWeekStart = _mondayOf(DateTime.now());
    _loadWeek();
    // Descarga puntual y escucha en tiempo real (sync entre dispositivos).
    _repo.pullFromFirebase().then((_) {
      if (mounted) _loadWeek();
    });
    _repo.startListening(
      onChanged: () {
        if (mounted) _loadWeek();
      },
    );
    // Propuestas de cambio de día que alguien me ha enviado.
    DateChangeService.instance.startListening(
      onChanged: () {
        if (mounted) _checkPendingDateChanges();
      },
    );
    DateChangeService.instance.pullPending().then((_) {
      if (mounted) _checkPendingDateChanges();
    });
  }

  @override
  void dispose() {
    _repo.stopListening();
    DateChangeService.instance.stopListening();
    super.dispose();
  }

  /// Si alguien ha movido de día un entrenamiento compartido, aquí se pregunta
  /// si acepto el cambio. Si soy el dueño y acepto, se mueve para todos.
  Future<void> _checkPendingDateChanges() async {
    if (!mounted) return;
    final answered = await showPendingDateChanges(
      context,
      'trainings',
      accent: _primary,
    );
    if (answered && mounted) _loadWeek();
  }

  /// Lunes (medianoche) de la semana de [d].
  /// Delegado en week_dates para que sea seguro frente al cambio de hora.
  DateTime _mondayOf(DateTime d) => mondayOf(d);

  // Evita que una carga antigua pise a una más reciente.
  int _loadToken = 0;

  /// Recarga la semana.
  ///
  /// [showSpinner] solo al CAMBIAR de semana. En el resto de recargas
  /// (marcar completado, cambios que llegan de Firebase…) no se muestra el
  /// spinner para que la lista no se reconstruya y el scroll no salte.
  Future<void> _loadWeek({bool showSpinner = false}) async {
    final token = ++_loadToken;
    if (showSpinner && mounted) setState(() => _isLoading = true);
    final entries = await _repo.getEntriesForWeek(_currentWeekStart);
    if (!mounted || token != _loadToken) return;
    setState(() {
      _entries = entries;
      _isLoading = false;
    });
  }

  Future<void> _openShareDialog() async {
    await showDialog(
      context: context,
      builder: (_) => const ShareWeeklyDialog(initialType: 'trainings'),
    );
    // Estampa el reparto global en mis entrenamientos ya existentes.
    await _repo.reapplyShares();
    _loadWeek();
  }

  // IMPORTANTE: se usa addDays (aritmética de calendario) y NO
  // Duration(days: 7). Duration suma 168 horas exactas y el día del cambio de
  // hora tiene 23 o 25, así que al cruzarlo _currentWeekStart dejaba de caer en
  // lunes a medianoche (pasaba a domingo 23:00) y la pantalla cargaba una
  // semana distinta de la que pintaba.
  void _prevWeek() {
    setState(() => _currentWeekStart = addDays(_currentWeekStart, -7));
    _loadWeek(showSpinner: true);
  }

  void _nextWeek() {
    setState(() => _currentWeekStart = addDays(_currentWeekStart, 7));
    _loadWeek(showSpinner: true);
  }

  String _weekLabel() => _fmtWeekRange(_currentWeekStart);

  List<WeeklyTrainingEntry> _entriesForDay(DateTime day) {
    final midnight = DateTime(
      day.year,
      day.month,
      day.day,
    ).millisecondsSinceEpoch;
    final endOfDay = DateTime(
      day.year,
      day.month,
      day.day,
      23,
      59,
      59,
    ).millisecondsSinceEpoch;
    return _entries
        .where((e) => e.date >= midnight && e.date <= endOfDay)
        .toList()
      ..sort((a, b) {
        if (a.isDone != b.isDone) return a.isDone ? 1 : -1;
        final order = WeeklyTrainingEntry.trainingTypes;
        final byType = order
            .indexOf(a.trainingType)
            .compareTo(order.indexOf(b.trainingType));
        if (byType != 0) return byType;
        return a.title.compareTo(b.title);
      });
  }

  // ══════════════════════════════════════════════════════════════════════════
  // COPIAR / PEGAR SEMANA
  // ══════════════════════════════════════════════════════════════════════════

  void _copyCurrentWeek() {
    final own = _entries
        .where((e) => e.ownerId == _myUid || e.ownerId.isEmpty)
        .toList();
    if (own.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No hay entrenamientos propios que copiar'),
        ),
      );
      return;
    }
    setState(() {
      _clipboard = List<WeeklyTrainingEntry>.from(own);
      _clipboardSourceMonday = _currentWeekStart;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${own.length} entrenamientos copiados. Ve a la semana destino y pulsa "Pegar aquí".',
        ),
        backgroundColor: Colors.deepOrange.shade400,
      ),
    );
  }

  Future<Set<String>> _inheritedShareUids(WeeklyTrainingEntry source) async {
    final uids = <String>{};
    try {
      uids.addAll(
        await WeeklyShareService.instance.getSharedUidsForItem(
          type: 'trainings',
          docId: source.id,
        ),
      );
    } catch (_) {}
    uids.addAll(WeeklyShareService.parseUids(source.sharedWith));
    uids
      ..remove(_myUid)
      ..remove('');
    return uids;
  }

  Future<void> _pasteIntoCurrentWeek() async {
    final clip = _clipboard;
    final source = _clipboardSourceMonday;
    if (clip == null || source == null) return;

    // daysBetween ignora horas y DST: difference().inDays daría 6 días
    // en una semana con cambio de hora.
    final offsetDays = daysBetween(source, _currentWeekStart);
    int sharedCount = 0;

    for (final e in clip) {
      final newDate = addDays(
        DateTime.fromMillisecondsSinceEpoch(e.date),
        offsetDays,
      );

      final inherited = await _inheritedShareUids(e);
      if (inherited.isNotEmpty) sharedCount++;

      final copy = e.copyWith(
        id: _repo.generateId(),
        date: newDate.millisecondsSinceEpoch,
        isDone: false,
        ownerId: '',
        ownerName: '',
        sharedWith: WeeklyShareService.uidsToJson(inherited),
        synced: 0,
      );
      await _repo.save(copy);
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          sharedCount > 0
              ? '${clip.length} entrenamientos pegados ($sharedCount se siguen compartiendo)'
              : '${clip.length} entrenamientos pegados en esta semana',
        ),
        backgroundColor: Colors.green.shade600,
      ),
    );
    _loadWeek();
  }

  void _cancelCopy() {
    setState(() {
      _clipboard = null;
      _clipboardSourceMonday = null;
    });
  }

  // ══════════════════════════════════════════════════════════════════════════
  // DIALOGS
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> _showCreateDialog({DateTime? preselectedDay}) async {
    DateTime selectedDay = preselectedDay ?? _currentWeekStart;
    String trainingType = WeeklyTrainingEntry.trainingTypes.first;
    RecurrenceRule rule = RecurrenceRule.none;
    String imageData = '';
    bool saving = false;
    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 24,
          ),
          title: const Text('Añadir entrenamiento'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Día',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  // Selector de día seguro frente al cambio de hora y con
                  // acceso al calendario completo ("Otra fecha…"), para poder
                  // crear en cualquier semana sin navegar con las flechas.
                  WeekDayPicker(
                    weekStart: _currentWeekStart,
                    selectedDay: selectedDay,
                    accent: _accent,
                    onChanged: (d) => setS(() => selectedDay = d),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Tipo',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 2,
                    children: WeeklyTrainingEntry.trainingTypes.map((t) {
                      return ChoiceChip(
                        label: Text(t),
                        selected: trainingType == t,
                        selectedColor: _accent.withOpacity(0.3),
                        onSelected: (_) => setS(() => trainingType = t),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: titleCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Ejercicio / Rutina *',
                      border: OutlineInputBorder(),
                    ),
                    textCapitalization: TextCapitalization.sentences,
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: descCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Series, repeticiones, peso… (opcional)',
                      border: OutlineInputBorder(),
                      alignLabelWithHint: true,
                    ),
                    minLines: 3,
                    maxLines: 6,
                    textCapitalization: TextCapitalization.sentences,
                  ),
                  const SizedBox(height: 12),
                  _TrainingImageField(
                    imageData: imageData,
                    heroTag: 'training_img_new',
                    accent: _primary,
                    onChanged: (v) => setS(() => imageData = v),
                  ),
                  const SizedBox(height: 12),
                  RecurrencePicker(
                    startDate: selectedDay,
                    accent: _accent,
                    onChanged: (r) => rule = r,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: _primary),
              onPressed: saving
                  ? null
                  : () async {
                      final title = titleCtrl.text.trim();
                      if (title.isEmpty) return;
                      setS(() => saving = true);
                      final entry = WeeklyTrainingEntry(
                        id: _repo.generateId(),
                        date: DateTime(
                          selectedDay.year,
                          selectedDay.month,
                          selectedDay.day,
                        ).millisecondsSinceEpoch,
                        trainingType: trainingType,
                        title: title,
                        description: descCtrl.text.trim(),
                        isDone: false,
                        ownerId: '',
                        imageData: imageData,
                      );
                      final created = await _repo.saveWithRecurrence(
                        entry,
                        rule,
                      );
                      if (ctx.mounted) Navigator.pop(ctx);
                      if (!mounted) return;
                      if (created > 1) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('$created entrenamientos creados'),
                            backgroundColor: Colors.green.shade600,
                          ),
                        );
                      }
                      // Si se ha creado en otra semana, saltamos a ella.
                      final newMonday = _mondayOf(selectedDay);
                      final changedWeek = !isSameDay(
                        newMonday,
                        _currentWeekStart,
                      );
                      setState(() => _currentWeekStart = newMonday);
                      _loadWeek(showSpinner: changedWeek);
                    },
              child: saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Guardar',
                      style: TextStyle(color: Colors.white),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showRemoveDialog() async {
    String scope = 'semana';
    DateTime selectedDay = _currentWeekStart;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Quitar entrenamiento'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioListTile<String>(
                title: const Text('Quitar toda la semana'),
                value: 'semana',
                groupValue: scope,
                onChanged: (v) => setS(() => scope = v!),
              ),
              RadioListTile<String>(
                title: const Text('Quitar un día concreto'),
                value: 'dia',
                groupValue: scope,
                onChanged: (v) => setS(() => scope = v!),
              ),
              if (scope == 'dia') ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  children: List.generate(7, (i) {
                    final day = addDays(_currentWeekStart, i);
                    final dayName = _fmtMedium(day);
                    final isSelected =
                        DateTime(day.year, day.month, day.day) ==
                        DateTime(
                          selectedDay.year,
                          selectedDay.month,
                          selectedDay.day,
                        );
                    return ChoiceChip(
                      label: Text(
                        dayName,
                        style: const TextStyle(fontSize: 12),
                      ),
                      selected: isSelected,
                      selectedColor: Colors.red.withOpacity(0.2),
                      onSelected: (_) => setS(() => selectedDay = day),
                    );
                  }),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
              ),
              onPressed: () async {
                if (scope == 'semana') {
                  await _repo.deleteWeek(_currentWeekStart);
                } else {
                  await _repo.deleteDay(selectedDay);
                }
                if (ctx.mounted) Navigator.pop(ctx);
                _loadWeek();
              },
              child: const Text(
                'Quitar',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showEditDialog(WeeklyTrainingEntry entry) async {
    final titleCtrl = TextEditingController(text: entry.title);
    final descCtrl = TextEditingController(text: entry.description);
    String trainingType = entry.trainingType;
    bool isDone = entry.isDone;
    String imageData = entry.imageData;
    final bool isForeign = entry.isSharedFromOther(_myUid);

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 24,
          ),
          title: Text(
            isForeign ? 'Detalle del entrenamiento' : 'Editar entrenamiento',
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isForeign)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 14),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.deepOrange.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: Colors.deepOrange.withOpacity(0.35),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.people_alt_outlined,
                            size: 18,
                            color: Colors.deepOrange,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Compartido por ${entry.ownerName.isNotEmpty ? entry.ownerName : "otra persona"}',
                              style: const TextStyle(
                                fontSize: 13,
                                color: Colors.deepOrange,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  // Completado (casilla, como en tareas)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Completado'),
                    activeColor: _primary,
                    value: isDone,
                    onChanged: (v) => setS(() => isDone = v),
                  ),
                  const SizedBox(height: 4),
                  if (!isForeign) ...[
                    const Text(
                      'Tipo',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 2,
                      children: WeeklyTrainingEntry.trainingTypes.map((t) {
                        return ChoiceChip(
                          label: Text(t),
                          selected: trainingType == t,
                          selectedColor: _accent.withOpacity(0.3),
                          onSelected: (_) => setS(() => trainingType = t),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextField(
                    controller: titleCtrl,
                    enabled: !isForeign,
                    decoration: const InputDecoration(
                      labelText: 'Ejercicio / Rutina',
                      border: OutlineInputBorder(),
                      alignLabelWithHint: true,
                    ),
                    minLines: 1,
                    maxLines: 4,
                    textCapitalization: TextCapitalization.sentences,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descCtrl,
                    enabled: !isForeign,
                    decoration: const InputDecoration(
                      labelText: 'Series, repeticiones, peso…',
                      border: OutlineInputBorder(),
                      alignLabelWithHint: true,
                    ),
                    minLines: 5,
                    maxLines: 12,
                  ),
                  const SizedBox(height: 12),
                  // Imagen: el dueño puede cambiarla; si es compartida solo
                  // se puede ver (pulsando se abre en grande).
                  _TrainingImageField(
                    imageData: imageData,
                    heroTag: 'training_img_edit_${entry.id}',
                    accent: _primary,
                    readOnly: isForeign,
                    onChanged: (v) => setS(() => imageData = v),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            // Un entrenamiento compartido conmigo NO se puede borrar:
            // solo se puede mover de día.
            if (!isForeign)
              TextButton(
                onPressed: () async {
                  await _repo.delete(entry.id);
                  if (ctx.mounted) Navigator.pop(ctx);
                  _loadWeek();
                },
                child: const Text(
                  'Eliminar',
                  style: TextStyle(color: Colors.redAccent),
                ),
              ),
            TextButton.icon(
              icon: const Icon(Icons.event_repeat, size: 18),
              label: const Text('Mover a…'),
              onPressed: () => _moveEntryToAnotherDay(ctx, entry, isForeign),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(isForeign ? 'Cerrar' : 'Cancelar'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: _primary),
              onPressed: () async {
                final title = titleCtrl.text.trim();
                if (title.isEmpty && !isForeign) return;
                await _repo.save(
                  entry.copyWith(
                    title: isForeign ? entry.title : title,
                    description: isForeign
                        ? entry.description
                        : descCtrl.text.trim(),
                    trainingType: isForeign ? entry.trainingType : trainingType,
                    isDone: isDone,
                    imageData: isForeign ? entry.imageData : imageData,
                    synced: 0,
                  ),
                );
                if (ctx.mounted) Navigator.pop(ctx);
                _loadWeek();
              },
              child: const Text(
                'Guardar',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
    _loadWeek();
  }

  /// Mueve un entrenamiento a otro día.
  ///
  /// · Propio      → cambia la fecha para todos los que lo tengan.
  /// · Compartido  → se me aplica a mí al momento y al dueño y al resto les
  ///   llega una propuesta que podrán aceptar o rechazar.
  Future<void> _moveEntryToAnotherDay(
    BuildContext ctx,
    WeeklyTrainingEntry entry,
    bool isForeign,
  ) async {
    final picked = await showDatePicker(
      context: ctx,
      initialDate: DateTime.fromMillisecondsSinceEpoch(entry.date),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;

    await _repo.moveToDay(entry, picked);
    if (ctx.mounted) Navigator.pop(ctx);

    if (mounted && isForeign) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Movido en tu semana. Se ha enviado la propuesta a quien lo comparte.',
          ),
        ),
      );
    }
    _loadWeek();
  }

  // ══════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ══════════════════════════════════════════════════════════════════════════

  Color _typeColor(String type) {
    switch (type) {
      case 'Pecho':
        return const Color(0xFFEF5350);
      case 'Espalda':
        return const Color(0xFF5C6BC0);
      case 'Pierna':
        return const Color(0xFF66BB6A);
      case 'Hombro':
        return const Color(0xFFFFA726);
      case 'Brazo':
        return const Color(0xFFAB47BC);
      case 'Core':
        return const Color(0xFF26A69A);
      case 'Cardio':
        return const Color(0xFFEC407A);
      case 'Full body':
        return const Color(0xFF42A5F5);
      case 'Estiramiento':
        return const Color(0xFF8D6E63);
      case 'Descanso':
        return Colors.blueGrey;
      default:
        return Colors.grey;
    }
  }

  IconData _typeIcon(String type) {
    switch (type) {
      case 'Pecho':
        return Icons.fitness_center;
      case 'Espalda':
        return Icons.rowing;
      case 'Pierna':
        return Icons.directions_run;
      case 'Hombro':
        return Icons.sports_gymnastics;
      case 'Brazo':
        return Icons.sports_mma;
      case 'Core':
        return Icons.self_improvement;
      case 'Cardio':
        return Icons.favorite;
      case 'Full body':
        return Icons.accessibility_new;
      case 'Estiramiento':
        return Icons.spa;
      case 'Descanso':
        return Icons.hotel;
      default:
        return Icons.sports;
    }
  }

  bool _isCurrentWeek() {
    final now = _mondayOf(DateTime.now());
    return now.year == _currentWeekStart.year &&
        now.month == _currentWeekStart.month &&
        now.day == _currentWeekStart.day;
  }

  bool _isToday(DateTime day) {
    final now = DateTime.now();
    return day.year == now.year && day.month == now.month && day.day == now.day;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: _primary,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Entrenamiento Semanal'),
        actions: [
          // Chapa con las propuestas de cambio de día pendientes.
          PendingDateChangesButton(
            type: 'trainings',
            accent: _primary,
            onResolved: _loadWeek,
          ),
          IconButton(
            tooltip: 'Compartir',
            icon: const Icon(Icons.people_outline),
            onPressed: _openShareDialog,
          ),
          IconButton(
            tooltip: 'Actualizar',
            icon: const Icon(Icons.sync),
            onPressed: _loadWeek,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildTopBar(),
          _buildActionButtons(),
          if (_clipboard != null) _buildPasteBanner(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _buildWeekList(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: _primary,
        foregroundColor: Colors.white,
        onPressed: () => _showCreateDialog(),
        icon: const Icon(Icons.add),
        label: const Text('Añadir'),
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      color: _primary,
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left, color: Colors.white),
            onPressed: _prevWeek,
            tooltip: 'Semana anterior',
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  _weekLabel(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                if (_isCurrentWeek())
                  Container(
                    margin: const EdgeInsets.only(top: 2),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'Semana actual',
                      style: TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right, color: Colors.white),
            onPressed: _nextWeek,
            tooltip: 'Semana siguiente',
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    final bool copying = _clipboard != null;
    return Container(
      color: _accent.withOpacity(0.15),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: _ActionBtn(
              icon: Icons.add_circle_outline,
              label: 'Crear',
              color: _primary,
              onTap: () => _showCreateDialog(),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _ActionBtn(
              icon: copying ? Icons.content_paste : Icons.copy_all,
              label: copying ? 'Pegar aquí' : 'Copiar',
              color: Colors.deepOrange,
              onTap: copying ? _pasteIntoCurrentWeek : _copyCurrentWeek,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _ActionBtn(
              icon: Icons.delete_outline,
              label: 'Quitar',
              color: Colors.redAccent,
              onTap: _showRemoveDialog,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPasteBanner() {
    return Container(
      width: double.infinity,
      color: Colors.deepOrange.withOpacity(0.12),
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      child: Row(
        children: [
          const Icon(Icons.content_copy, size: 18, color: Colors.deepOrange),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Copiaste la semana del ${_fmtShort(_clipboardSourceMonday!)}. '
              'Navega con las flechas y pulsa "Pegar aquí".',
              style: const TextStyle(fontSize: 12, color: Colors.deepOrange),
            ),
          ),
          TextButton(
            onPressed: _cancelCopy,
            child: const Text('Cancelar', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _buildWeekList() {
    // Resumen global de la semana (todos los entrenamientos).
    final totalDone = _entries.where((e) => e.isDone).length;
    final totalAll = _entries.length;

    return ListView.builder(
      // La clave por semana conserva la posición del scroll al recargar.
      key: PageStorageKey<String>(
        'trainings_${_currentWeekStart.millisecondsSinceEpoch}',
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 100),
      itemCount: 8, // 7 días + 1 resumen al inicio
      itemBuilder: (ctx, index) {
        if (index == 0) {
          return _WeekSummary(
            done: totalDone,
            total: totalAll,
            color: _primary,
          );
        }
        final day = addDays(_currentWeekStart, index - 1);
        final dayEntries = _entriesForDay(day);
        final isToday = _isToday(day);
        return _TrainingDayCard(
          day: day,
          entries: dayEntries,
          isToday: isToday,
          primaryColor: _primary,
          myUid: _myUid,
          onAddTap: () => _showCreateDialog(preselectedDay: day),
          onEntryTap: _showEditDialog,
          onToggle: (e) async {
            // Cambio optimista: se pinta al instante sin recargar la lista.
            setState(() {
              _entries = [
                for (final x in _entries)
                  x.id == e.id ? x.copyWith(isDone: !e.isDone) : x,
              ];
            });
            try {
              await _repo.toggleDone(e);
            } catch (err) {
              debugPrint('❌ toggleDone falló: $err');
            }
            if (mounted) _loadWeek(); // recarga silenciosa (sin spinner)
          },
          typeColor: _typeColor,
          typeIcon: _typeIcon,
        );
      },
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// WIDGETS AUXILIARES
// ════════════════════════════════════════════════════════════════════════════

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionBtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withOpacity(0.1),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WeekSummary extends StatelessWidget {
  final int done;
  final int total;
  final Color color;

  const _WeekSummary({
    required this.done,
    required this.total,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    if (total == 0) return const SizedBox.shrink();
    final pct = total == 0 ? 0.0 : done / total;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.bar_chart, color: color),
                const SizedBox(width: 8),
                Text(
                  'Resumen de la semana',
                  style: TextStyle(fontWeight: FontWeight.w700, color: color),
                ),
                const Spacer(),
                Text(
                  '${(pct * 100).round()}%',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '$done / $total completados',
              style: const TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: pct,
                minHeight: 8,
                backgroundColor: Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrainingDayCard extends StatelessWidget {
  final DateTime day;
  final List<WeeklyTrainingEntry> entries;
  final bool isToday;
  final Color primaryColor;
  final String myUid;
  final VoidCallback onAddTap;
  final void Function(WeeklyTrainingEntry) onEntryTap;
  final void Function(WeeklyTrainingEntry) onToggle;
  final Color Function(String) typeColor;
  final IconData Function(String) typeIcon;

  const _TrainingDayCard({
    required this.day,
    required this.entries,
    required this.isToday,
    required this.primaryColor,
    this.myUid = '',
    required this.onAddTap,
    required this.onEntryTap,
    required this.onToggle,
    required this.typeColor,
    required this.typeIcon,
  });

  @override
  Widget build(BuildContext context) {
    final dayName = _diasSemana[day.weekday - 1];
    final dayFormatted = _fmtShort(day);
    final headerColor = isToday ? primaryColor : Colors.grey.shade700;

    final doneCount = entries.where((e) => e.isDone).length;
    final totalCount = entries.length;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: isToday ? 4 : 1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            decoration: BoxDecoration(
              color: isToday
                  ? primaryColor.withOpacity(0.12)
                  : Colors.grey.shade100,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(14),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
            child: Row(
              children: [
                if (isToday)
                  Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: primaryColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                Text(
                  '${dayName[0].toUpperCase()}${dayName.substring(1)}',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: headerColor,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  dayFormatted,
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                ),
                const Spacer(),
                if (totalCount > 0)
                  Container(
                    margin: const EdgeInsets.only(right: 4),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: doneCount == totalCount
                          ? Colors.green.withOpacity(0.15)
                          : primaryColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$doneCount/$totalCount',
                      style: TextStyle(
                        fontSize: 12,
                        color: doneCount == totalCount
                            ? Colors.green
                            : primaryColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                IconButton(
                  icon: Icon(Icons.add, color: primaryColor, size: 20),
                  onPressed: onAddTap,
                  tooltip: 'Añadir entrenamiento',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
          // Entradas
          if (entries.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              child: Text(
                'Sin entrenamiento planificado',
                style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
              ),
            )
          else
            Column(
              children: [
                for (var i = 0; i < entries.length; i++) ...[
                  _entryTile(entries[i]),
                  if (i != entries.length - 1)
                    Divider(
                      height: 1,
                      indent: 16,
                      endIndent: 16,
                      color: Colors.grey.shade200,
                    ),
                ],
              ],
            ),
        ],
      ),
    );
  }

  Widget _entryTile(WeeklyTrainingEntry e) {
    final color = typeColor(e.trainingType);
    final shared = e.isSharedFromOther(myUid);

    return ListTile(
      isThreeLine: e.description.isNotEmpty || e.hasImage,
      titleAlignment: ListTileTitleAlignment.top,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      // Casilla de completado (como en tareas) + icono de tipo.
      leading: SizedBox(
        width: 66,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: () => onToggle(e),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: e.isDone ? primaryColor : Colors.transparent,
                  border: Border.all(
                    color: e.isDone ? primaryColor : Colors.grey.shade400,
                    width: 2,
                  ),
                ),
                child: e.isDone
                    ? const Icon(Icons.check, size: 14, color: Colors.white)
                    : null,
              ),
            ),
            const SizedBox(width: 6),
            Stack(
              clipBehavior: Clip.none,
              children: [
                CircleAvatar(
                  radius: 15,
                  backgroundColor: color.withOpacity(0.15),
                  child: Icon(typeIcon(e.trainingType), size: 15, color: color),
                ),
                if (shared)
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: Colors.deepOrange,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                      child: const Icon(
                        Icons.people_alt,
                        size: 9,
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
      title: Text(
        e.title,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 14.5,
          height: 1.25,
          decoration: e.isDone ? TextDecoration.lineThrough : null,
          color: e.isDone ? Colors.grey : null,
        ),
        maxLines: 4,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: (e.description.isNotEmpty || e.hasImage)
          ? Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (e.description.isNotEmpty)
                    Text(
                      e.description,
                      style: TextStyle(
                        fontSize: 12,
                        color: e.isDone ? Colors.grey.shade400 : null,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  // Miniatura: al pulsarla se abre a pantalla completa.
                  if (e.hasImage)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Base64Thumb(
                        base64Data: e.imageData,
                        heroTag: 'training_img_${e.id}',
                        width: 120,
                        height: 80,
                      ),
                    ),
                ],
              ),
            )
          : null,
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          e.trainingType,
          style: TextStyle(
            fontSize: 11,
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      onTap: () => onEntryTap(e),
    );
  }
}

/// Campo de imagen para los diálogos de crear/editar entrenamiento.
/// Muestra la miniatura (pulsar = ver en grande) y los botones de
/// añadir / cambiar / quitar.
class _TrainingImageField extends StatelessWidget {
  final String imageData;
  final String heroTag;
  final Color accent;
  final bool readOnly;
  final ValueChanged<String> onChanged;

  const _TrainingImageField({
    required this.imageData,
    required this.heroTag,
    required this.accent,
    required this.onChanged,
    this.readOnly = false,
  });

  Future<void> _pick(BuildContext context) async {
    final bytes = await pickCompressedImage(context);
    if (bytes != null) onChanged(Base64ImageCache.encode(bytes));
  }

  @override
  Widget build(BuildContext context) {
    final hasImage = imageData.isNotEmpty;
    if (readOnly && !hasImage) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Imagen', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        if (hasImage)
          Base64Thumb(
            base64Data: imageData,
            heroTag: heroTag,
            width: double.infinity,
            height: 160,
          ),
        if (hasImage)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              'Pulsa la imagen para verla en grande',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
          ),
        if (!readOnly)
          Wrap(
            spacing: 8,
            children: [
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: accent),
                onPressed: () => _pick(context),
                icon: Icon(
                  hasImage ? Icons.swap_horiz : Icons.add_photo_alternate,
                ),
                label: Text(hasImage ? 'Cambiar imagen' : 'Añadir imagen'),
              ),
              if (hasImage)
                TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                  ),
                  onPressed: () => onChanged(''),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Quitar'),
                ),
            ],
          ),
      ],
    );
  }
}
