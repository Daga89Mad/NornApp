// lib/views/weekly_tasks_screen.dart

import 'package:nornapp/views/share_weekly_dialog.dart';
import 'package:flutter/material.dart';
import '../models/weekly_task_model.dart';
import '../core/weekly_task_repository.dart';
import '../core/weekly_share_service.dart';
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

  int _doneCountForDay(DateTime day) =>
      _tasksForDay(day).where((t) => t.isDone).length;
  int _totalCountForDay(DateTime day) => _tasksForDay(day).length;

  // ══════════════════════════════════════════════════════════════════════════
  // DIALOGS
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> _showCreateDialog({DateTime? preselectedDay}) async {
    DateTime selectedDay = preselectedDay ?? _currentWeekStart;
    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Crear tarea'),
          content: SingleChildScrollView(
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
                  ),
                  maxLines: 2,
                  textCapitalization: TextCapitalization.sentences,
                ),
              ],
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
                );
                await _repo.save(task);
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

  Future<void> _showAssignDialog() async {
    // Asignar: copiar tareas de otra semana a la semana actual
    DateTime sourceWeek = _currentWeekStart.subtract(const Duration(days: 7));
    List<WeeklyTask> sourceTasks = [];

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Asignar tareas'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Copia las tareas de otra semana a la semana actual (se restablece el estado a pendiente).',
                  style: TextStyle(fontSize: 13, color: Colors.grey),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left),
                      onPressed: () {
                        setS(
                          () => sourceWeek = sourceWeek.subtract(
                            const Duration(days: 7),
                          ),
                        );
                      },
                    ),
                    Expanded(
                      child: Text(
                        _weekLabelOf(sourceWeek),
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right),
                      onPressed: () {
                        setS(
                          () => sourceWeek = sourceWeek.add(
                            const Duration(days: 7),
                          ),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: () async {
                    final tasks = await _repo.getTasksForWeek(sourceWeek);
                    setS(() => sourceTasks = tasks);
                  },
                  icon: const Icon(Icons.search),
                  label: const Text('Ver tareas de esa semana'),
                  style: ElevatedButton.styleFrom(backgroundColor: _accent),
                ),
                if (sourceTasks.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    '${sourceTasks.length} tareas encontradas',
                    style: const TextStyle(
                      color: Colors.green,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Sin tareas en esa semana',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: _primary),
              onPressed: sourceTasks.isEmpty
                  ? null
                  : () async {
                      final offsetDays = _currentWeekStart
                          .difference(sourceWeek)
                          .inDays;
                      for (final t in sourceTasks) {
                        final newDate = DateTime.fromMillisecondsSinceEpoch(
                          t.date,
                        ).add(Duration(days: offsetDays));
                        final newTask = t.copyWith(
                          id: _repo.generateId(),
                          date: DateTime(
                            newDate.year,
                            newDate.month,
                            newDate.day,
                          ).millisecondsSinceEpoch,
                          isDone: false,
                          synced: 0,
                        );
                        await _repo.save(newTask);
                      }
                      if (ctx.mounted) Navigator.pop(ctx);
                      _loadWeek();
                    },
              child: const Text(
                'Copiar tareas',
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

  Future<void> _showEditDialog(WeeklyTask task) async {
    final titleCtrl = TextEditingController(text: task.title);
    final descCtrl = TextEditingController(text: task.description);

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Editar tarea'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleCtrl,
              decoration: const InputDecoration(
                labelText: 'Tarea',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: descCtrl,
              decoration: const InputDecoration(
                labelText: 'Descripción',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
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
            child: const Text('Guardar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ══════════════════════════════════════════════════════════════════════════

  String _weekLabelOf(DateTime monday) => _fmtWeekRange(monday);

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
              icon: Icons.copy_all,
              label: 'Asignar',
              color: Colors.blueGrey,
              onTap: _showAssignDialog,
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

  Widget _buildWeekList() {
    // Resumen global de la semana
    final totalDone = _tasks.where((t) => t.isDone).length;
    final totalAll = _tasks.length;

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
            await _repo.toggleDone(t);
            _loadWeek();
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
    final doneCount = tasks.where((t) => t.isDone).length;
    final totalCount = tasks.length;
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
          if (tasks.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              child: Text(
                'Sin tareas para este día',
                style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: tasks.length,
              separatorBuilder: (_, __) => Divider(
                height: 1,
                indent: 16,
                endIndent: 16,
                color: Colors.grey.shade200,
              ),
              itemBuilder: (_, i) {
                final t = tasks[i];
                return ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 2,
                  ),
                  leading: GestureDetector(
                    onTap: () => onToggle(t),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: t.isDone ? primaryColor : Colors.transparent,
                        border: Border.all(
                          color: t.isDone ? primaryColor : Colors.grey.shade400,
                          width: 2,
                        ),
                      ),
                      child: t.isDone
                          ? const Icon(
                              Icons.check,
                              size: 14,
                              color: Colors.white,
                            )
                          : null,
                    ),
                  ),
                  title: Row(
                    children: [
                      if (t.isSharedFromOther(myUid)) ...[
                        Container(
                          margin: const EdgeInsets.only(right: 6),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.teal.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: Colors.teal.withOpacity(0.4),
                            ),
                          ),
                          child: Text(
                            t.ownerName.isNotEmpty ? t.ownerName : 'Compartido',
                            style: const TextStyle(
                              fontSize: 9,
                              color: Colors.teal,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                      Expanded(
                        child: Text(
                          t.title,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            decoration: t.isDone
                                ? TextDecoration.lineThrough
                                : null,
                            color: t.isDone ? Colors.grey : null,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  subtitle: t.description.isNotEmpty
                      ? Text(
                          t.description,
                          style: TextStyle(
                            fontSize: 12,
                            color: t.isDone ? Colors.grey.shade400 : null,
                          ),
                        )
                      : null,
                  trailing: IconButton(
                    icon: Icon(
                      Icons.edit_outlined,
                      size: 18,
                      color: Colors.grey.shade500,
                    ),
                    onPressed: () => onEditTap(t),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                  ),
                  onTap: () => onToggle(t),
                );
              },
            ),
        ],
      ),
    );
  }
}
