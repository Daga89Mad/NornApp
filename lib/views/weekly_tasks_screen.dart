// lib/views/weekly_tasks_screen.dart

import 'package:nornapp/views/share_weekly_dialog.dart';
import 'package:flutter/material.dart';
import '../models/weekly_task_model.dart';
import '../models/friend_model.dart';
import '../core/weekly_task_repository.dart';
import '../core/weekly_share_service.dart';
import '../core/friend_repository.dart';
import 'package:firebase_auth/firebase_auth.dart';

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
  final sunday = monday.add(const Duration(days: 6));
  return '${_fmtShort(monday)} – ${_fmtShort(sunday)}';
}

class WeeklyTasksScreen extends StatefulWidget {
  const WeeklyTasksScreen({Key? key}) : super(key: key);

  @override
  State<WeeklyTasksScreen> createState() => _WeeklyTasksScreenState();
}

class _WeeklyTasksScreenState extends State<WeeklyTasksScreen> {
  final _repo = WeeklyTaskRepository.instance;

  late DateTime _currentWeekStart;
  List<WeeklyTask> _tasks = [];
  bool _isLoading = true;
  String _myUid = '';

  // Portapapeles para copiar/pegar semanas
  List<WeeklyTask>? _clipboard;
  DateTime? _clipboardSourceMonday;

  static const Color _primary = Color(0xFF00897B); // teal
  static const Color _accent = Color(0xFF26A69A);

  @override
  void initState() {
    super.initState();
    _myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    _currentWeekStart = _mondayOf(DateTime.now());
    _loadWeek();
    WeeklyShareService.instance.startListening(
      onChanged: () {
        if (mounted) _loadWeek();
      },
    );
  }

  @override
  void dispose() {
    WeeklyShareService.instance.stopListening();
    super.dispose();
  }

  DateTime _mondayOf(DateTime d) {
    final monday = d.subtract(Duration(days: d.weekday - 1));
    return DateTime(monday.year, monday.month, monday.day);
  }

  Future<void> _loadWeek() async {
    setState(() => _isLoading = true);
    final tasks = await _repo.getTasksForWeek(_currentWeekStart);
    setState(() {
      _tasks = tasks;
      _isLoading = false;
    });
  }

  Future<void> _openShareDialog() async {
    await showDialog(
      context: context,
      builder: (_) => const ShareWeeklyDialog(initialType: 'tasks'),
    );
    await _repo.reapplyShares();
    _loadWeek();
  }

  void _prevWeek() {
    setState(
      () => _currentWeekStart = _currentWeekStart.subtract(
        const Duration(days: 7),
      ),
    );
    _loadWeek();
  }

  void _nextWeek() {
    setState(
      () => _currentWeekStart = _currentWeekStart.add(const Duration(days: 7)),
    );
    _loadWeek();
  }

  String _weekLabel() => _fmtWeekRange(_currentWeekStart);

  List<WeeklyTask> _tasksForDay(DateTime day) {
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
    return _tasks
        .where((t) => t.date >= midnight && t.date <= endOfDay)
        .toList()
      ..sort((a, b) {
        if (a.isDone != b.isDone) return a.isDone ? 1 : -1;
        return a.title.compareTo(b.title);
      });
  }

  // ══════════════════════════════════════════════════════════════════════════
  // COPIAR / PEGAR SEMANA (con subtareas)
  // ══════════════════════════════════════════════════════════════════════════

  void _copyCurrentWeek() {
    final own = _tasks
        .where((t) => t.ownerId == _myUid || t.ownerId.isEmpty)
        .toList();
    if (own.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay tareas propias que copiar')),
      );
      return;
    }
    setState(() {
      _clipboard = List<WeeklyTask>.from(own);
      _clipboardSourceMonday = _currentWeekStart;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${own.length} tareas copiadas. Ve a la semana destino y pulsa "Pegar aquí".',
        ),
        backgroundColor: Colors.teal.shade700,
      ),
    );
  }

  Future<void> _pasteIntoCurrentWeek() async {
    final clip = _clipboard;
    final source = _clipboardSourceMonday;
    if (clip == null || source == null) return;

    final offsetDays = _currentWeekStart.difference(source).inDays;

    int newDateOf(WeeklyTask t) {
      final d = DateTime.fromMillisecondsSinceEpoch(
        t.date,
      ).add(Duration(days: offsetDays));
      return DateTime(d.year, d.month, d.day).millisecondsSinceEpoch;
    }

    // 1) Copiar primero las tareas principales, mapeando id viejo → id nuevo.
    final idMap = <String, String>{};
    for (final t in clip.where((t) => t.parentId.isEmpty)) {
      final newId = _repo.generateId();
      idMap[t.id] = newId;
      await _repo.save(
        t.copyWith(
          id: newId,
          date: newDateOf(t),
          isDone: false,
          ownerId: '',
          ownerName: '',
          sharedWith: '',
          parentId: '',
          synced: 0,
        ),
      );
    }

    // 2) Copiar subtareas, apuntando al nuevo id del padre (o suelta si no está).
    for (final t in clip.where((t) => t.parentId.isNotEmpty)) {
      final newParent = idMap[t.parentId] ?? '';
      await _repo.save(
        t.copyWith(
          id: _repo.generateId(),
          date: newDateOf(t),
          isDone: false,
          ownerId: '',
          ownerName: '',
          sharedWith: '',
          parentId: newParent,
          synced: 0,
        ),
      );
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${clip.length} tareas pegadas en esta semana'),
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
  String recurrence = 'none';
  Future<void> _showCreateDialog({DateTime? preselectedDay}) async {
    DateTime selectedDay = preselectedDay ?? _currentWeekStart;
    recurrence = 'none';
    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 24,
          ),
          title: const Text('Crear tarea'),
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
                  Wrap(
                    spacing: 6,
                    children: List.generate(7, (i) {
                      final day = _currentWeekStart.add(Duration(days: i));
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
                        selectedColor: _accent.withOpacity(0.3),
                        onSelected: (_) => setS(() => selectedDay = day),
                      );
                    }),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: titleCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Tarea *',
                      border: OutlineInputBorder(),
                    ),
                    textCapitalization: TextCapitalization.sentences,
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: descCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Descripción (opcional)',
                      border: OutlineInputBorder(),
                      alignLabelWithHint: true,
                    ),
                    minLines: 3,
                    maxLines: 6,
                    textCapitalization: TextCapitalization.sentences,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Repetir',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    children:
                        [
                          ('none', 'No repetir'),
                          ('daily', 'Cada día'),
                          ('weekly', 'Cada semana'),
                        ].map((opt) {
                          return ChoiceChip(
                            label: Text(
                              opt.$2,
                              style: const TextStyle(fontSize: 12),
                            ),
                            selected: recurrence == opt.$1,
                            selectedColor: _accent.withOpacity(0.3),
                            onSelected: (_) => setS(() => recurrence = opt.$1),
                          );
                        }).toList(),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: _primary),
              onPressed: () async {
                final title = titleCtrl.text.trim();
                if (title.isEmpty) return;
                final task = WeeklyTask(
                  id: _repo.generateId(),
                  date: DateTime(
                    selectedDay.year,
                    selectedDay.month,
                    selectedDay.day,
                  ).millisecondsSinceEpoch,
                  title: title,
                  description: descCtrl.text.trim(),
                  ownerId: '',
                  recurrence: recurrence,
                );
                await _repo.saveWithRecurrence(task);
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
  }

  Future<void> _showRemoveDialog() async {
    String scope = 'semana';
    DateTime selectedDay = _currentWeekStart;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Quitar tareas'),
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
                    final day = _currentWeekStart.add(Duration(days: i));
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

  // ── Popup de detalle/edición ampliado con subtareas ───────────────────────
  Future<void> _showEditDialog(WeeklyTask task) async {
    final titleCtrl = TextEditingController(text: task.title);
    final descCtrl = TextEditingController(text: task.description);
    final subCtrl = TextEditingController();
    final bool isForeign = task.isSharedFromOther(_myUid);
    final bool isParent = task.parentId.isEmpty;

    final friends = await FriendRepository.instance.getAll();
    Set<String> sharedUids = WeeklyShareService.parseUids(task.sharedWith);
    List<WeeklyTask> subtasks = isParent
        ? await _repo.getSubtasks(task.id)
        : <WeeklyTask>[];

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          Future<void> reloadSubs() async {
            subtasks = await _repo.getSubtasks(task.id);
            setS(() {});
          }

          return AlertDialog(
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 24,
            ),
            title: Text(isForeign ? 'Detalle de la tarea' : 'Editar tarea'),
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
                          color: Colors.teal.withOpacity(0.10),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: Colors.teal.withOpacity(0.35),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.people_alt_outlined,
                              size: 18,
                              color: Colors.teal,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Compartido por ${task.ownerName.isNotEmpty ? task.ownerName : "otra persona"}',
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Colors.teal,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    TextField(
                      controller: titleCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Tarea',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: descCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Descripción',
                        border: OutlineInputBorder(),
                        alignLabelWithHint: true,
                      ),
                      minLines: 6,
                      maxLines: 12,
                    ),

                    // ── Subtareas (solo para tareas principales) ──────────────
                    if (isParent) ...[
                      const SizedBox(height: 16),
                      const Divider(),
                      Row(
                        children: const [
                          Icon(Icons.checklist, size: 18),
                          SizedBox(width: 8),
                          Text(
                            'Subtareas',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      if (subtasks.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(left: 4, bottom: 4),
                          child: Text(
                            'Sin subtareas todavía',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        )
                      else
                        ...subtasks.map(
                          (s) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 1),
                            child: Row(
                              children: [
                                InkWell(
                                  onTap: () async {
                                    await _repo.toggleDone(s);
                                    await reloadSubs();
                                  },
                                  child: Icon(
                                    s.isDone
                                        ? Icons.check_circle
                                        : Icons.radio_button_unchecked,
                                    size: 20,
                                    color: s.isDone ? _primary : Colors.grey,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    s.title,
                                    style: TextStyle(
                                      fontSize: 13,
                                      decoration: s.isDone
                                          ? TextDecoration.lineThrough
                                          : null,
                                      color: s.isDone ? Colors.grey : null,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    size: 18,
                                    color: Colors.redAccent,
                                  ),
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () async {
                                    await _repo.delete(s.id);
                                    await reloadSubs();
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: subCtrl,
                              decoration: const InputDecoration(
                                hintText: 'Nueva subtarea…',
                                isDense: true,
                                border: OutlineInputBorder(),
                              ),
                              textCapitalization: TextCapitalization.sentences,
                              onSubmitted: (_) async {
                                await _repo.addSubtask(task, subCtrl.text);
                                subCtrl.clear();
                                await reloadSubs();
                              },
                            ),
                          ),
                          const SizedBox(width: 6),
                          IconButton(
                            icon: const Icon(Icons.add_circle),
                            color: _primary,
                            onPressed: () async {
                              await _repo.addSubtask(task, subCtrl.text);
                              subCtrl.clear();
                              await reloadSubs();
                            },
                          ),
                        ],
                      ),
                    ],

                    // ── Compartir esta tarea suelta (solo si es mía) ──────────
                    if (!isForeign) ...[
                      const SizedBox(height: 16),
                      const Divider(),
                      Row(
                        children: [
                          const Icon(Icons.share_outlined, size: 18),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Compartir solo esta tarea',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          TextButton.icon(
                            icon: const Icon(Icons.person_add_alt, size: 18),
                            label: const Text('Elegir'),
                            onPressed: () async {
                              final updated = await _pickFriendsForItem(
                                friends: friends,
                                alreadyShared: sharedUids,
                                docId: task.id,
                              );
                              if (updated != null) {
                                setS(() => sharedUids = updated);
                              }
                            },
                          ),
                        ],
                      ),
                      if (sharedUids.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 2, left: 4),
                          child: Text(
                            'No compartida individualmente',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        )
                      else
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: sharedUids.map((uid) {
                            final f = friends.firstWhere(
                              (fr) => fr.firebaseUid == uid,
                              orElse: () => FriendModel(
                                name: 'Amigo',
                                email: '',
                                firebaseUid: uid,
                              ),
                            );
                            return Chip(
                              label: Text(
                                f.displayName,
                                style: const TextStyle(fontSize: 12),
                              ),
                              onDeleted: () async {
                                await WeeklyShareService.instance
                                    .unshareSingleItem(
                                      type: 'tasks',
                                      docId: task.id,
                                      friendUid: uid,
                                    );
                                setS(() => sharedUids.remove(uid));
                              },
                            );
                          }).toList(),
                        ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  await _repo.delete(task.id);
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
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate: DateTime.fromMillisecondsSinceEpoch(task.date),
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                  );
                  if (picked == null) return;
                  await _repo.moveToDay(task, picked);
                  if (ctx.mounted) Navigator.pop(ctx);
                  _loadWeek();
                },
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: _primary),
                onPressed: () async {
                  final title = titleCtrl.text.trim();
                  if (title.isEmpty) return;
                  await _repo.save(
                    task.copyWith(
                      title: title,
                      description: descCtrl.text.trim(),
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
          );
        },
      ),
    );
    _loadWeek();
  }

  Future<Set<String>?> _pickFriendsForItem({
    required List<FriendModel> friends,
    required Set<String> alreadyShared,
    required String docId,
  }) async {
    final valid = friends.where((f) => f.firebaseUid != null).toList();
    if (valid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No tienes amigos para compartir')),
      );
      return null;
    }
    final selected = Set<String>.from(alreadyShared);

    return showDialog<Set<String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Compartir esta tarea'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: valid.map((f) {
                final uid = f.firebaseUid!;
                final isSel = selected.contains(uid);
                return CheckboxListTile(
                  value: isSel,
                  title: Text(f.displayName),
                  subtitle: Text(f.email, style: const TextStyle(fontSize: 11)),
                  secondary: Text(f.logo, style: const TextStyle(fontSize: 20)),
                  onChanged: (v) async {
                    if (v == true) {
                      await WeeklyShareService.instance.shareSingleItem(
                        type: 'tasks',
                        docId: docId,
                        friendUid: uid,
                      );
                      setS(() => selected.add(uid));
                    } else {
                      await WeeklyShareService.instance.unshareSingleItem(
                        type: 'tasks',
                        docId: docId,
                        friendUid: uid,
                      );
                      setS(() => selected.remove(uid));
                    }
                  },
                );
              }).toList(),
            ),
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: _primary),
              onPressed: () => Navigator.pop(ctx, selected),
              child: const Text('Listo', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ══════════════════════════════════════════════════════════════════════════

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
        title: const Text('Tareas Semanales'),
        actions: [
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
        icon: const Icon(Icons.add_task),
        label: const Text('Añadir tarea'),
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
      color: _accent.withOpacity(0.12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: _ActionBtn(
              icon: Icons.add_task,
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
              color: Colors.blueGrey,
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
      color: Colors.teal.withOpacity(0.12),
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      child: Row(
        children: [
          const Icon(Icons.content_copy, size: 18, color: Colors.teal),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Copiaste la semana del ${_fmtShort(_clipboardSourceMonday!)}. '
              'Navega con las flechas y pulsa "Pegar aquí".',
              style: const TextStyle(fontSize: 12, color: Colors.teal),
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
    // Resumen global de la semana (solo tareas principales).
    final parents = _tasks.where((t) => t.parentId.isEmpty).toList();
    final totalDone = parents.where((t) => t.isDone).length;
    final totalAll = parents.length;

    return ListView.builder(
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
        final day = _currentWeekStart.add(Duration(days: index - 1));
        final dayTasks = _tasksForDay(day);
        final isToday = _isToday(day);
        return _TaskDayCard(
          day: day,
          tasks: dayTasks,
          isToday: isToday,
          primaryColor: _primary,
          myUid: _myUid,
          onAddTap: () => _showCreateDialog(preselectedDay: day),
          onToggle: (t) async {
            try {
              await _repo.toggleDone(t);
            } catch (e) {
              debugPrint('❌ toggleDone falló: $e');
            }
            if (mounted) _loadWeek();
          },
          onEditTap: _showEditDialog,
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
                  '$done / $total completadas',
                  style: const TextStyle(fontSize: 13, color: Colors.grey),
                ),
              ],
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

class _TaskDayCard extends StatelessWidget {
  final DateTime day;
  final List<WeeklyTask> tasks;
  final bool isToday;
  final Color primaryColor;
  final String myUid;
  final VoidCallback onAddTap;
  final void Function(WeeklyTask) onToggle;
  final void Function(WeeklyTask) onEditTap;

  const _TaskDayCard({
    required this.day,
    required this.tasks,
    required this.isToday,
    required this.primaryColor,
    this.myUid = '',
    required this.onAddTap,
    required this.onToggle,
    required this.onEditTap,
  });

  @override
  Widget build(BuildContext context) {
    final dayName = _diasSemana[day.weekday - 1];
    final dayFormatted = _fmtShort(day);

    // Separar principales y subtareas.
    final parents = tasks.where((t) => t.parentId.isEmpty).toList();
    final subsByParent = <String, List<WeeklyTask>>{};
    for (final t in tasks.where((t) => t.parentId.isNotEmpty)) {
      subsByParent.putIfAbsent(t.parentId, () => []).add(t);
    }

    final doneCount = parents.where((t) => t.isDone).length;
    final totalCount = parents.length;
    final headerColor = isToday ? primaryColor : Colors.grey.shade700;

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
                  tooltip: 'Añadir tarea',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
          // Tareas
          if (parents.isEmpty && subsByParent.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              child: Text(
                'Sin tareas para este día',
                style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
              ),
            )
          else
            Builder(
              builder: (_) {
                final parentIds = parents.map((p) => p.id).toSet();
                final orphans = <WeeklyTask>[
                  for (final entry in subsByParent.entries)
                    if (!parentIds.contains(entry.key)) ...entry.value,
                ];
                return Column(
                  children: [
                    for (final t in parents) ...[
                      _taskTile(t, subs: subsByParent[t.id] ?? const []),
                      for (final s in (subsByParent[t.id] ?? const []))
                        _taskTile(s, isSub: true),
                      Divider(
                        height: 1,
                        indent: 16,
                        endIndent: 16,
                        color: Colors.grey.shade200,
                      ),
                    ],
                    // Subtareas cuyo padre no está visible este día:
                    // se muestran como tareas normales para no perderlas.
                    for (final o in orphans) _taskTile(o),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _taskTile(
    WeeklyTask t, {
    bool isSub = false,
    List<WeeklyTask> subs = const [],
  }) {
    final shared = t.isSharedFromOther(myUid);
    final subDone = subs.where((s) => s.isDone).length;

    return ListTile(
      dense: isSub,
      isThreeLine: !isSub && t.description.isNotEmpty,
      contentPadding: EdgeInsets.only(left: isSub ? 44 : 12, right: 12),
      leading: SizedBox(
        width: isSub ? 22 : 36,
        height: isSub ? 22 : 36,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            GestureDetector(
              onTap: () => onToggle(t),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: isSub ? 20 : 24,
                height: isSub ? 20 : 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: t.isDone ? primaryColor : Colors.transparent,
                  border: Border.all(
                    color: t.isDone ? primaryColor : Colors.grey.shade400,
                    width: 2,
                  ),
                ),
                child: t.isDone
                    ? const Icon(Icons.check, size: 13, color: Colors.white)
                    : null,
              ),
            ),
            if (shared && !isSub)
              Positioned(
                right: -2,
                bottom: -2,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: Colors.teal,
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
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              t.title,
              style: TextStyle(
                fontWeight: isSub ? FontWeight.w500 : FontWeight.w600,
                fontSize: isSub ? 13 : 14,
                decoration: t.isDone ? TextDecoration.lineThrough : null,
                color: t.isDone ? Colors.grey : null,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (!isSub && subs.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(left: 6),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '$subDone/${subs.length}',
                style: TextStyle(
                  fontSize: 10,
                  color: primaryColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
      // Descripción: hasta 3 líneas visibles (solo en principales).
      subtitle: (!isSub && t.description.isNotEmpty)
          ? Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                t.description,
                style: TextStyle(
                  fontSize: 12,
                  color: t.isDone ? Colors.grey.shade400 : null,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            )
          : null,
      trailing: isSub
          ? null
          : IconButton(
              icon: Icon(
                Icons.edit_outlined,
                size: 18,
                color: Colors.grey.shade500,
              ),
              onPressed: () => onEditTap(t),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
            ),
      onTap: () => isSub ? onToggle(t) : onEditTap(t),
    );
  }
}
