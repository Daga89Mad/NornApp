// lib/views/weekly_menu_screen.dart

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/weekly_menu_model.dart';
import '../core/weekly_menu_repository.dart';
import '../core/weekly_share_service.dart';
import 'share_weekly_dialog.dart';

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

class WeeklyMenuScreen extends StatefulWidget {
  const WeeklyMenuScreen({Key? key}) : super(key: key);

  @override
  State<WeeklyMenuScreen> createState() => _WeeklyMenuScreenState();
}

class _WeeklyMenuScreenState extends State<WeeklyMenuScreen> {
  final _repo = WeeklyMenuRepository.instance;

  late DateTime _currentWeekStart;
  List<WeeklyMenuEntry> _entries = [];
  bool _isLoading = true;
  String _myUid = '';

  static const Color _primary = Color(0xFF5C6BC0);
  static const Color _accent = Color(0xFF7986CB);

  @override
  void initState() {
    super.initState();
    _myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    _currentWeekStart = _mondayOf(DateTime.now());
    _loadWeek();
    // Escuchar cambios en tiempo real de menús compartidos conmigo
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
    final entries = await _repo.getEntriesForWeek(_currentWeekStart);
    setState(() {
      _entries = entries;
      _isLoading = false;
    });
  }

  Future<void> _openShareDialog() async {
    await showDialog(
      context: context,
      builder: (_) => const ShareWeeklyDialog(initialType: 'menus'),
    );
    _loadWeek(); // Recargar por si acaso cambiaron las preferencias de compartir
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

  List<WeeklyMenuEntry> _entriesForDay(DateTime day) {
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
        const order = ['Desayuno', 'Almuerzo', 'Merienda', 'Cena', 'Otro'];
        return order.indexOf(a.mealType).compareTo(order.indexOf(b.mealType));
      });
  }

  // ══════════════════════════════════════════════════════════════════════════
  // DIALOGS
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> _showCreateDialog({DateTime? preselectedDay}) async {
    DateTime selectedDay = preselectedDay ?? _currentWeekStart;
    String mealType = WeeklyMenuEntry.mealTypes.first;
    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Crear menú'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Selector de día
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
                // Tipo de comida
                const Text(
                  'Tipo',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  children: WeeklyMenuEntry.mealTypes.map((t) {
                    return ChoiceChip(
                      label: Text(t),
                      selected: mealType == t,
                      selectedColor: _accent.withOpacity(0.3),
                      onSelected: (_) => setS(() => mealType = t),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Plato / Menú *',
                    border: OutlineInputBorder(),
                  ),
                  textCapitalization: TextCapitalization.sentences,
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: descCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Notas (opcional)',
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
                final entry = WeeklyMenuEntry(
                  id: _repo.generateId(),
                  date: DateTime(
                    selectedDay.year,
                    selectedDay.month,
                    selectedDay.day,
                  ).millisecondsSinceEpoch,
                  mealType: mealType,
                  title: title,
                  description: descCtrl.text.trim(),
                  ownerId: '',
                );
                await _repo.save(entry);
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
    // Asignar: copiar menús de otra semana a la semana actual
    DateTime sourceWeek = _currentWeekStart.subtract(const Duration(days: 7));
    List<WeeklyMenuEntry> sourceEntries = [];

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Asignar menú'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Copia los menús de otra semana a la semana actual.',
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
                    final entries = await _repo.getEntriesForWeek(sourceWeek);
                    setS(() => sourceEntries = entries);
                  },
                  icon: const Icon(Icons.search),
                  label: const Text('Ver menús de esa semana'),
                  style: ElevatedButton.styleFrom(backgroundColor: _accent),
                ),
                if (sourceEntries.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    '${sourceEntries.length} entradas encontradas',
                    style: const TextStyle(
                      color: Colors.green,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ] else if (sourceEntries.isEmpty) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Sin entradas en esa semana',
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
              onPressed: sourceEntries.isEmpty
                  ? null
                  : () async {
                      // Calcular offset de días entre semanas
                      final offsetDays = _currentWeekStart
                          .difference(sourceWeek)
                          .inDays;
                      for (final e in sourceEntries) {
                        final newDate = DateTime.fromMillisecondsSinceEpoch(
                          e.date,
                        ).add(Duration(days: offsetDays));
                        final newEntry = e.copyWith(
                          id: _repo.generateId(),
                          date: DateTime(
                            newDate.year,
                            newDate.month,
                            newDate.day,
                          ).millisecondsSinceEpoch,
                          synced: 0,
                        );
                        await _repo.save(newEntry);
                      }
                      if (ctx.mounted) Navigator.pop(ctx);
                      _loadWeek();
                    },
              child: const Text(
                'Copiar menús',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showRemoveDialog() async {
    String scope = 'semana'; // 'semana' o 'dia'
    DateTime selectedDay = _currentWeekStart;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Quitar menú'),
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

  Future<void> _showEditDialog(WeeklyMenuEntry entry) async {
    final titleCtrl = TextEditingController(text: entry.title);
    final descCtrl = TextEditingController(text: entry.description);
    String mealType = entry.mealType;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Editar entrada'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Wrap(
                  spacing: 6,
                  children: WeeklyMenuEntry.mealTypes.map((t) {
                    return ChoiceChip(
                      label: Text(t),
                      selected: mealType == t,
                      selectedColor: _accent.withOpacity(0.3),
                      onSelected: (_) => setS(() => mealType = t),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Plato / Menú',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: descCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Notas',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
              ],
            ),
          ),
          actions: [
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
                  entry.copyWith(
                    title: title,
                    description: descCtrl.text.trim(),
                    mealType: mealType,
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
  }

  // ══════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ══════════════════════════════════════════════════════════════════════════

  String _weekLabelOf(DateTime monday) => _fmtWeekRange(monday);

  Color _mealTypeColor(String type) {
    switch (type) {
      case 'Desayuno':
        return const Color(0xFFFFA726);
      case 'Almuerzo':
        return const Color(0xFF42A5F5);
      case 'Merienda':
        return const Color(0xFF66BB6A);
      case 'Cena':
        return const Color(0xFFAB47BC);
      default:
        return Colors.grey;
    }
  }

  IconData _mealTypeIcon(String type) {
    switch (type) {
      case 'Desayuno':
        return Icons.free_breakfast;
      case 'Almuerzo':
        return Icons.lunch_dining;
      case 'Merienda':
        return Icons.cake;
      case 'Cena':
        return Icons.dinner_dining;
      default:
        return Icons.restaurant;
    }
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
        title: const Text('Menú Semanal'),
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

  bool _isCurrentWeek() {
    final now = _mondayOf(DateTime.now());
    return now.year == _currentWeekStart.year &&
        now.month == _currentWeekStart.month &&
        now.day == _currentWeekStart.day;
  }

  Widget _buildActionButtons() {
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
              icon: Icons.copy_all,
              label: 'Asignar',
              color: Colors.teal,
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
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 100),
      itemCount: 7,
      itemBuilder: (ctx, index) {
        final day = _currentWeekStart.add(Duration(days: index));
        final dayEntries = _entriesForDay(day);
        final isToday = _isToday(day);
        return _DayCard(
          day: day,
          entries: dayEntries,
          isToday: isToday,
          primaryColor: _primary,
          myUid: _myUid,
          onAddTap: () => _showCreateDialog(preselectedDay: day),
          onEntryTap: _showEditDialog,
          mealTypeColor: _mealTypeColor,
          mealTypeIcon: _mealTypeIcon,
        );
      },
    );
  }

  bool _isToday(DateTime day) {
    final now = DateTime.now();
    return day.year == now.year && day.month == now.month && day.day == now.day;
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

class _DayCard extends StatelessWidget {
  final DateTime day;
  final List<WeeklyMenuEntry> entries;
  final bool isToday;
  final Color primaryColor;
  final String myUid;
  final VoidCallback onAddTap;
  final void Function(WeeklyMenuEntry) onEntryTap;
  final Color Function(String) mealTypeColor;
  final IconData Function(String) mealTypeIcon;

  const _DayCard({
    required this.day,
    required this.entries,
    required this.isToday,
    required this.primaryColor,
    this.myUid = '',
    required this.onAddTap,
    required this.onEntryTap,
    required this.mealTypeColor,
    required this.mealTypeIcon,
  });

  @override
  Widget build(BuildContext context) {
    final dayName = _diasSemana[day.weekday - 1];
    final dayFormatted = _fmtShort(day);
    final headerColor = isToday ? primaryColor : Colors.grey.shade700;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: isToday ? 4 : 1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header del día
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
                IconButton(
                  icon: Icon(Icons.add, color: primaryColor, size: 20),
                  onPressed: onAddTap,
                  tooltip: 'Añadir plato',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
          // Entradas del día
          if (entries.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              child: Text(
                'Sin menú planificado',
                style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: entries.length,
              separatorBuilder: (_, __) => Divider(
                height: 1,
                indent: 16,
                endIndent: 16,
                color: Colors.grey.shade200,
              ),
              itemBuilder: (_, i) {
                final e = entries[i];
                final color = mealTypeColor(e.mealType);
                return ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 2,
                  ),
                  leading: CircleAvatar(
                    radius: 16,
                    backgroundColor: color.withOpacity(0.15),
                    child: Icon(
                      mealTypeIcon(e.mealType),
                      size: 16,
                      color: color,
                    ),
                  ),
                  title: Row(
                    children: [
                      if (e.isSharedFromOther(myUid)) ...[
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
                            e.ownerName.isNotEmpty ? e.ownerName : 'Compartido',
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
                          e.title,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  subtitle: e.description.isNotEmpty
                      ? Text(
                          e.description,
                          style: const TextStyle(fontSize: 12),
                        )
                      : null,
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      e.mealType,
                      style: TextStyle(
                        fontSize: 11,
                        color: color,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  onTap: () => onEntryTap(e),
                );
              },
            ),
        ],
      ),
    );
  }
}
