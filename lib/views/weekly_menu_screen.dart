// lib/views/weekly_menu_screen.dart

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/weekly_menu_model.dart';
import '../models/friend_model.dart';
import '../core/weekly_menu_repository.dart';
import '../core/weekly_share_service.dart';
import '../core/friend_repository.dart';
import 'shopping_list_screen.dart';
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

  // ── Portapapeles para copiar/pegar semanas ────────────────────────────────
  List<WeeklyMenuEntry>? _clipboard;
  DateTime? _clipboardSourceMonday;

  static const Color _primary = Color(0xFF5C6BC0);
  static const Color _accent = Color(0xFF7986CB);

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
    _loadWeek();
  }

  void _openShoppingList() {
    // Usa el mes del jueves de la semana visible como "mes de la semana",
    // así una semana a caballo entre dos meses se asigna al mes mayoritario.
    final reference = _currentWeekStart.add(const Duration(days: 3));
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ShoppingListScreen(initialMonth: reference),
      ),
    );
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
        const order = [
          'Desayuno',
          'Media mañana',
          'Almuerzo',
          'Merienda',
          'Cena',
          'Otro',
        ];
        return order.indexOf(a.mealType).compareTo(order.indexOf(b.mealType));
      });
  }

  // ══════════════════════════════════════════════════════════════════════════
  // COPIAR / PEGAR SEMANA
  // ══════════════════════════════════════════════════════════════════════════

  void _copyCurrentWeek() {
    // Copiamos solo los menús propios de la semana visible.
    final own = _entries
        .where((e) => e.ownerId == _myUid || e.ownerId.isEmpty)
        .toList();
    if (own.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay menús propios que copiar')),
      );
      return;
    }
    setState(() {
      _clipboard = List<WeeklyMenuEntry>.from(own);
      _clipboardSourceMonday = _currentWeekStart;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${own.length} menús copiados. Ve a la semana destino y pulsa "Pegar aquí".',
        ),
        backgroundColor: Colors.teal.shade600,
      ),
    );
  }

  Future<void> _pasteIntoCurrentWeek() async {
    final clip = _clipboard;
    final source = _clipboardSourceMonday;
    if (clip == null || source == null) return;

    final offsetDays = _currentWeekStart.difference(source).inDays;
    for (final e in clip) {
      final newDate = DateTime.fromMillisecondsSinceEpoch(
        e.date,
      ).add(Duration(days: offsetDays));
      // Reseteamos propiedad → se guardan como míos y se sincronizan de cero.
      final copy = e.copyWith(
        id: _repo.generateId(),
        date: DateTime(
          newDate.year,
          newDate.month,
          newDate.day,
        ).millisecondsSinceEpoch,
        ownerId: '',
        ownerName: '',
        sharedWith: '',
        synced: 0,
      );
      await _repo.save(copy);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${clip.length} menús pegados en esta semana'),
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
    String mealType = WeeklyMenuEntry.mealTypes.first;
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
          title: const Text('Crear menú'),
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
                      alignLabelWithHint: true,
                    ),
                    minLines: 3,
                    maxLines: 6,
                    textCapitalization: TextCapitalization.sentences,
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

  Future<void> _showRemoveDialog() async {
    String scope = 'semana';
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

  // ── Popup de detalle/edición ampliado ─────────────────────────────────────
  Future<void> _showEditDialog(WeeklyMenuEntry entry) async {
    final titleCtrl = TextEditingController(text: entry.title);
    final descCtrl = TextEditingController(text: entry.description);
    String mealType = entry.mealType;
    final bool isForeign = entry.isSharedFromOther(_myUid);

    // Cargamos amigos para poder mostrar/gestionar el compartir individual.
    final friends = await FriendRepository.instance.getAll();
    Set<String> sharedUids = WeeklyShareService.parseUids(entry.sharedWith);

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 24,
          ),
          title: Text(isForeign ? 'Detalle del menú' : 'Editar menú'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Aviso de quién lo compartió contigo
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
                              'Compartido por ${entry.ownerName.isNotEmpty ? entry.ownerName : "otra persona"}',
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
                      alignLabelWithHint: true,
                    ),
                    minLines: 1,
                    maxLines: 4,
                    textCapitalization: TextCapitalization.sentences,
                  ),
                  const SizedBox(height: 12),
                  // Caja de descripción grande (mínimo 6 líneas visibles)
                  TextField(
                    controller: descCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Notas',
                      border: OutlineInputBorder(),
                      alignLabelWithHint: true,
                    ),
                    minLines: 6,
                    maxLines: 12,
                  ),

                  // Compartir este menú suelto (solo si es mío)
                  if (!isForeign) ...[
                    const SizedBox(height: 16),
                    const Divider(),
                    Row(
                      children: [
                        const Icon(Icons.share_outlined, size: 18),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Compartir solo este menú',
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
                              docId: entry.id,
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
                          'No compartido individualmente',
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
                                    type: 'menus',
                                    docId: entry.id,
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
    _loadWeek();
  }

  /// Selector de amigos para compartir un item concreto. Devuelve el nuevo set
  /// de UIDs compartidos, o null si se canceló.
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
          title: const Text('Compartir este menú'),
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
                        type: 'menus',
                        docId: docId,
                        friendUid: uid,
                      );
                      setS(() => selected.add(uid));
                    } else {
                      await WeeklyShareService.instance.unshareSingleItem(
                        type: 'menus',
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

  Color _mealTypeColor(String type) {
    switch (type) {
      case 'Desayuno':
        return const Color(0xFFFFA726);
      case 'Media mañana':
        return const Color(0xFFFFCA28);
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
      case 'Media mañana':
        return Icons.bakery_dining;
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
            tooltip: 'Lista de la compra',
            icon: const Icon(Icons.shopping_cart_outlined),
            onPressed: _openShoppingList,
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

  bool _isCurrentWeek() {
    final now = _mondayOf(DateTime.now());
    return now.year == _currentWeekStart.year &&
        now.month == _currentWeekStart.month &&
        now.day == _currentWeekStart.day;
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
              color: Colors.teal,
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
                final shared = e.isSharedFromOther(myUid);
                return ListTile(
                  isThreeLine: e.description.isNotEmpty,
                  titleAlignment: ListTileTitleAlignment.top,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  // Avatar con badge de "compartido" en la esquina.
                  leading: SizedBox(
                    width: 36,
                    height: 36,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: color.withOpacity(0.15),
                          child: Icon(
                            mealTypeIcon(e.mealType),
                            size: 16,
                            color: color,
                          ),
                        ),
                        if (shared)
                          Positioned(
                            right: -2,
                            bottom: -2,
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                color: Colors.teal,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white,
                                  width: 1.5,
                                ),
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
                  title: Text(
                    e.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14.5,
                      height: 1.25,
                    ),
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                  ),
                  // Descripción: hasta 3 líneas visibles.
                  subtitle: e.description.isNotEmpty
                      ? Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            e.description,
                            style: const TextStyle(fontSize: 12),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
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
