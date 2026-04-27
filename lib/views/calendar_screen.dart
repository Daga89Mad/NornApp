// lib/views/calendar_screen.dart

import 'package:flutter/material.dart';
import '../models/event_item.dart';
import '../models/shift_model.dart';
import '../core/event_repository.dart';
import '../core/shift_repository.dart';
import '../core/shift_assignment_repository.dart'
    show ShiftAssignmentRepository, SharedShiftInfo;
import 'package:firebase_auth/firebase_auth.dart';
import '../core/settings_repository.dart';
import '../core/friend_repository.dart';
import '../core/firebase_sync_service.dart';
import '../models/friend_model.dart';
import 'day_view.dart';
import 'share_calendar_dialog.dart';
import 'dart:math' as math;

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({Key? key}) : super(key: key);

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime _focusedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime? _selectedDay;
  final ScrollController _horizontalController = ScrollController();

  Map<DateTime, List<EventItem>> _events = {};
  Map<DateTime, List<ShiftModel>> _shiftsByDay = {};
  bool _eventsLoading = true;

  // Preferencias
  bool _filterTrabajo = true;
  bool _filterEventos = true;
  bool _filterCitas = true;
  bool _filterRecordatorios = true;
  bool _filterBebe = true;
  bool _filterPeriodo = true;
  bool _filterTurnos = true;
  bool _compactMode = false;
  String _selectedBgName = 'Blanco';
  String _selectedDesign = 'Predeterminado';
  bool _settingsLoaded = false;

  // ── Amigos con eventos compartidos ────────────────────────────────────────
  List<FriendModel> _friendsWithSharedEvents = [];
  Set<String> _hiddenFriendUids = {};
  String? _myUid;
  Map<DateTime, List<SharedShiftInfo>> _sharedShiftsByDay = {};

  // ── Modo asignación masiva de turnos ──────────────────────────────────────
  ShiftModel? _assigningShift;
  Set<DateTime> _existingShiftDays = {};
  Set<DateTime> _pendingDays = {};
  bool _loadingAssignment = false;

  // ── Altura mínima de celda en modo compacto ───────────────────────────────
  // 72 px garantiza que caben: número + badge de turno + punto + "+N"
  // sin overflow. Si la pantalla da más espacio, se usa el mayor.
  static const double _kMinCompactCellH = 72.0;

  final Map<String, Color> _bgOptions = {
    'Blanco': Colors.white,
    'Gris claro': const Color(0xFFF5F5F5),
    'Marfil': const Color(0xFFFFF8E1),
    'Azul claro': const Color(0xFFE3F2FD),
    'Verde claro': const Color(0xFFE8F5E9),
    'Rosa claro': const Color(0xFFFCE4EC),
    'Oscuro (modo noche)': const Color(0xFF121212),
  };
  Color get _backgroundColor => _bgOptions[_selectedBgName] ?? Colors.white;

  final List<String> _designOptions = ['Predeterminado', 'Líneas', '3D suave'];

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _horizontalController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    _myUid = FirebaseAuth.instance.currentUser?.uid;
    await _loadSettings();
    await _loadMonth(_focusedMonth);
    await _loadFriendsWithSharedEvents();

    if (_myUid != null) {
      FirebaseSyncService.instance.startListening(
        _myUid!,
        onSharedEventReceived: () {
          if (mounted) _loadMonth(_focusedMonth);
        },
      );
    }
  }

  // ── Settings ───────────────────────────────────────────────────────────────

  Future<void> _loadSettings() async {
    final s = await SettingsRepository.instance.getCalendarSettings();
    if (!mounted) return;
    setState(() {
      _filterTrabajo = s.filterTrabajo;
      _filterEventos = s.filterEventos;
      _filterCitas = s.filterCitas;
      _filterRecordatorios = s.filterRecordatorios;
      _filterBebe = s.filterBebe;
      _filterPeriodo = s.filterPeriodo;
      _compactMode = s.compactMode;
      _selectedBgName = _bgOptions.containsKey(s.bgName) ? s.bgName : 'Blanco';
      _selectedDesign = _designOptions.contains(s.design)
          ? s.design
          : 'Predeterminado';
      _settingsLoaded = true;
    });
  }

  Future<void> _saveSettings() async {
    await SettingsRepository.instance.saveCalendarSettings(
      CalendarSettings(
        filterTrabajo: _filterTrabajo,
        filterEventos: _filterEventos,
        filterCitas: _filterCitas,
        filterRecordatorios: _filterRecordatorios,
        filterBebe: _filterBebe,
        filterPeriodo: _filterPeriodo,
        compactMode: _compactMode,
        bgName: _selectedBgName,
        design: _selectedDesign,
      ),
    );
  }

  // ── Amigos con eventos compartidos ────────────────────────────────────────

  Future<void> _loadFriendsWithSharedEvents() async {
    if (_myUid == null) return;
    final allFriends = await FriendRepository.instance.getAll();
    final Set<String> ownerUids = {};
    for (final events in _events.values) {
      for (final e in events) {
        if (e.ownerId != null && e.ownerId != _myUid) ownerUids.add(e.ownerId!);
      }
    }
    for (final shifts in _sharedShiftsByDay.values) {
      for (final s in shifts) {
        ownerUids.add(s.ownerUid);
      }
    }
    final withShared = allFriends
        .where(
          (f) => f.firebaseUid != null && ownerUids.contains(f.firebaseUid),
        )
        .toList();
    if (mounted) setState(() => _friendsWithSharedEvents = withShared);
  }

  bool _isSharedEvent(EventItem e) => e.ownerId != null && e.ownerId != _myUid;

  FriendModel? _friendForEvent(EventItem e) {
    if (!_isSharedEvent(e)) return null;
    try {
      return _friendsWithSharedEvents.firstWhere(
        (f) => f.firebaseUid == e.ownerId,
      );
    } catch (_) {
      return null;
    }
  }

  // ── Data ───────────────────────────────────────────────────────────────────

  Future<void> _loadMonth(DateTime month) async {
    setState(() => _eventsLoading = true);
    try {
      final results = await Future.wait([
        EventRepository.instance.getEventsForMonth(month.year, month.month),
        ShiftAssignmentRepository.instance.getShiftsForMonth(
          month.year,
          month.month,
        ),
        ShiftAssignmentRepository.instance.getSharedShiftsForMonth(
          month.year,
          month.month,
        ),
      ]);
      if (mounted) {
        setState(() {
          _events = results[0] as Map<DateTime, List<EventItem>>;
          _shiftsByDay = results[1] as Map<DateTime, List<ShiftModel>>;
          _sharedShiftsByDay =
              results[2] as Map<DateTime, List<SharedShiftInfo>>;
        });
      }
    } catch (e) {
      debugPrint('Error cargando mes: $e');
    } finally {
      if (mounted) setState(() => _eventsLoading = false);
      await _loadFriendsWithSharedEvents();
    }
  }

  // ── Navegación mes ─────────────────────────────────────────────────────────

  void _prevMonthAction() {
    final m = DateTime(_focusedMonth.year, _focusedMonth.month - 1);
    setState(() => _focusedMonth = m);
    _loadMonth(m);
  }

  void _nextMonthAction() {
    final m = DateTime(_focusedMonth.year, _focusedMonth.month + 1);
    setState(() => _focusedMonth = m);
    _loadMonth(m);
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  List<EventItem> _eventsForDay(DateTime day) {
    final key = DateTime.utc(day.year, day.month, day.day);
    final all = _events[key] ?? [];
    return all.where((e) {
      if (e.ownerId != null && _hiddenFriendUids.contains(e.ownerId)) {
        return false;
      }
      if (_filterTrabajo && e.category == Category.Laboral) return true;
      if (_filterEventos && e.category == Category.Evento) return true;
      if (_filterCitas && e.category == Category.Cita) return true;
      if (_filterRecordatorios && e.category == Category.Recordatorio)
        return true;
      if (_filterBebe && e.category == Category.Bebe) return true;
      if (_filterPeriodo && e.category == Category.Periodo) return true;
      return false;
    }).toList();
  }

  List<SharedShiftInfo> _sharedShiftsForDay(DateTime day) {
    if (_hiddenFriendUids.isNotEmpty) {
      final key = DateTime.utc(day.year, day.month, day.day);
      return (_sharedShiftsByDay[key] ?? [])
          .where((s) => !_hiddenFriendUids.contains(s.ownerUid))
          .toList();
    }
    final key = DateTime.utc(day.year, day.month, day.day);
    return _sharedShiftsByDay[key] ?? [];
  }

  List<ShiftModel> _shiftsForDay(DateTime day) {
    if (!_filterTurnos) return [];
    final key = DateTime.utc(day.year, day.month, day.day);
    return _shiftsByDay[key] ?? [];
  }

  String _monthLabel(DateTime m) {
    const names = [
      'Ene',
      'Feb',
      'Mar',
      'Abr',
      'May',
      'Jun',
      'Jul',
      'Ago',
      'Sep',
      'Oct',
      'Nov',
      'Dic',
    ];
    return '${names[m.month - 1]} ${m.year}';
  }

  // ── Widget: turno 3D ──────────────────────────────────────────────────────

  Widget _shiftBadge(ShiftModel shift, {bool compact = false}) {
    final c = shift.color;
    return Container(
      margin: const EdgeInsets.only(right: 3, bottom: 2),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 4 : 6,
        vertical: compact ? 1 : 2,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color.lerp(Colors.white, c, 0.7)!, c],
        ),
        boxShadow: [
          BoxShadow(
            color: c.withOpacity(0.45),
            offset: const Offset(0, 2),
            blurRadius: 3,
            spreadRadius: 0,
          ),
          BoxShadow(
            color: Colors.white.withOpacity(0.35),
            offset: const Offset(0, -1),
            blurRadius: 1,
          ),
        ],
      ),
      child: Text(
        compact
            ? (shift.name.length > 3 ? shift.name.substring(0, 3) : shift.name)
            : shift.name,
        style: TextStyle(
          color: Colors.white,
          fontSize: compact ? 8 : 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
          shadows: const [
            Shadow(color: Colors.black26, offset: Offset(0, 1), blurRadius: 1),
          ],
        ),
        overflow: TextOverflow.clip,
        maxLines: 1,
      ),
    );
  }

  // ── Badge de turno compartido ─────────────────────────────────────────────

  Widget _sharedShiftBadge(SharedShiftInfo shift, {bool compact = false}) {
    final c = shift.color;
    String logo = '👤';
    for (final f in _friendsWithSharedEvents) {
      if (f.firebaseUid == shift.ownerUid) {
        logo = f.logo;
        break;
      }
    }
    final shortName = shift.name.length > 3
        ? shift.name.substring(0, 3)
        : shift.name;
    return Container(
      margin: const EdgeInsets.only(right: 3, bottom: 2),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 3 : 5,
        vertical: compact ? 1 : 2,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color.lerp(Colors.white, c, 0.6)!, c.withOpacity(0.85)],
        ),
        border: Border.all(color: Colors.red.shade400, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: c.withOpacity(0.4),
            offset: const Offset(0, 2),
            blurRadius: 3,
            spreadRadius: 0,
          ),
          BoxShadow(
            color: Colors.white.withOpacity(0.3),
            offset: const Offset(0, -1),
            blurRadius: 1,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            logo,
            style: TextStyle(
              fontSize: compact ? 7 : 9,
              shadows: const [
                Shadow(
                  color: Colors.black26,
                  offset: Offset(0, 1),
                  blurRadius: 1,
                ),
              ],
            ),
          ),
          const SizedBox(width: 2),
          Text(
            compact ? shortName : shift.name,
            style: TextStyle(
              color: Colors.white,
              fontSize: compact ? 8 : 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
              shadows: const [
                Shadow(
                  color: Colors.black26,
                  offset: Offset(0, 1),
                  blurRadius: 1,
                ),
              ],
            ),
            overflow: TextOverflow.clip,
            maxLines: 1,
          ),
        ],
      ),
    );
  }

  // ── Decoración de celda ────────────────────────────────────────────────────

  BoxDecoration _cellDecoration({
    required bool isSelected,
    required bool isToday,
  }) {
    if (_selectedDesign == 'Líneas') {
      return BoxDecoration(
        color: isSelected
            ? Theme.of(context).colorScheme.primary.withOpacity(0.08)
            : null,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.grey.shade300, width: 1),
      );
    } else if (_selectedDesign == '3D suave') {
      return BoxDecoration(
        gradient: isSelected
            ? LinearGradient(
                colors: [
                  Colors.white,
                  Theme.of(context).colorScheme.primary.withOpacity(0.06),
                ],
              )
            : LinearGradient(
                colors: [_backgroundColor.withOpacity(0.98), _backgroundColor],
              ),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            offset: const Offset(0, 4),
            blurRadius: 8,
          ),
          BoxShadow(
            color: Colors.white.withOpacity(0.6),
            offset: const Offset(-2, -2),
            blurRadius: 4,
          ),
        ],
        border: isToday
            ? Border.all(
                color: Theme.of(context).colorScheme.primary,
                width: 1.2,
              )
            : null,
      );
    } else {
      return BoxDecoration(
        color: isSelected
            ? Theme.of(context).colorScheme.primary.withOpacity(0.12)
            : null,
        borderRadius: BorderRadius.circular(8),
        border: isToday
            ? Border.all(
                color: Theme.of(context).colorScheme.primary,
                width: 1.2,
              )
            : null,
      );
    }
  }

  // ── Botón filtro de amigos ────────────────────────────────────────────────

  Widget _buildFriendFilterButton() {
    if (_friendsWithSharedEvents.isEmpty) return const SizedBox.shrink();
    final anyHidden = _hiddenFriendUids.isNotEmpty;
    return Tooltip(
      message: 'Filtrar por amigo',
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: _openFriendFilter,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(
                Icons.people_outlined,
                size: 20,
                color: anyHidden ? Colors.blue.shade600 : Colors.black54,
              ),
              if (anyHidden)
                Positioned(
                  top: -3,
                  right: -3,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Colors.blue,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _openFriendFilter() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _FriendFilterSheet(
        friends: _friendsWithSharedEvents,
        hiddenUids: Set<String>.from(_hiddenFriendUids),
        onChanged: (hidden) {
          setState(() => _hiddenFriendUids = hidden);
        },
      ),
    );
  }

  void _openShareDialog() {
    showDialog(context: context, builder: (_) => const ShareCalendarDialog());
  }

  // ── Asignación masiva de turnos ───────────────────────────────────────────

  Future<void> _loadExistingShiftDays(ShiftModel shift) async {
    setState(() => _loadingAssignment = true);
    final monthMap = await ShiftAssignmentRepository.instance.getShiftsForMonth(
      _focusedMonth.year,
      _focusedMonth.month,
    );
    final Set<DateTime> days = {};
    for (final entry in monthMap.entries) {
      if (entry.value.any((s) => s.id == shift.id)) {
        days.add(entry.key);
      }
    }
    if (mounted) {
      setState(() {
        _existingShiftDays = days;
        _pendingDays = Set.from(days);
        _loadingAssignment = false;
      });
    }
  }

  Future<void> _openShiftAssignmentSheet() async {
    final shifts = await ShiftRepository.instance.getAll();
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _ShiftPickerSheet(
        shifts: shifts,
        onSelected: (shift) {
          Navigator.pop(context);
          setState(() {
            _assigningShift = shift;
            _existingShiftDays = {};
            _pendingDays = {};
          });
          _loadExistingShiftDays(shift);
        },
      ),
    );
  }

  Future<void> _confirmShiftAssignment() async {
    final shift = _assigningShift;
    if (shift?.id == null) return;
    setState(() => _loadingAssignment = true);

    final toAdd = _pendingDays.difference(_existingShiftDays);
    final toRemove = _existingShiftDays.difference(_pendingDays);

    for (final day in toAdd) {
      final assigned = await ShiftAssignmentRepository.instance
          .getAssignedShiftIds(day);
      if (!assigned.contains(shift!.id)) {
        await ShiftAssignmentRepository.instance.toggle(shift.id!, day);
      }
    }
    for (final day in toRemove) {
      final assigned = await ShiftAssignmentRepository.instance
          .getAssignedShiftIds(day);
      if (assigned.contains(shift!.id)) {
        await ShiftAssignmentRepository.instance.toggle(shift.id!, day);
      }
    }

    if (mounted) {
      setState(() {
        _assigningShift = null;
        _existingShiftDays = {};
        _pendingDays = {};
        _loadingAssignment = false;
      });
      await _loadMonth(_focusedMonth);
    }
  }

  void _cancelShiftAssignment() {
    setState(() {
      _assigningShift = null;
      _existingShiftDays = {};
      _pendingDays = {};
    });
  }

  Widget _buildAssignShiftButton() {
    final bool active = _assigningShift != null;
    return Tooltip(
      message: 'Asignar turno al mes',
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: active ? null : _openShiftAssignmentSheet,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Icon(
            Icons.edit_calendar_outlined,
            size: 20,
            color: active ? Colors.teal : Colors.black54,
          ),
        ),
      ),
    );
  }

  // ── Menú 3 puntos ──────────────────────────────────────────────────────────

  Widget _buildFilterSummaryMenu() {
    final items = [
      _FilterEntry('Trabajo', Icons.work_outline, Colors.blue, _filterTrabajo, (
        v,
      ) {
        setState(() => _filterTrabajo = v);
        _saveSettings();
      }),
      _FilterEntry('Eventos', Icons.celebration, Colors.amber, _filterEventos, (
        v,
      ) {
        setState(() => _filterEventos = v);
        _saveSettings();
      }),
      _FilterEntry(
        'Citas',
        Icons.medical_services,
        Colors.orange,
        _filterCitas,
        (v) {
          setState(() => _filterCitas = v);
          _saveSettings();
        },
      ),
      _FilterEntry(
        'Recordatorios',
        Icons.notifications,
        Colors.red,
        _filterRecordatorios,
        (v) {
          setState(() => _filterRecordatorios = v);
          _saveSettings();
        },
      ),
      _FilterEntry('Bebé', Icons.child_care, Colors.pink, _filterBebe, (v) {
        setState(() => _filterBebe = v);
        _saveSettings();
      }),
      _FilterEntry(
        'Período',
        Icons.favorite,
        Colors.deepPurple,
        _filterPeriodo,
        (v) {
          setState(() => _filterPeriodo = v);
          _saveSettings();
        },
      ),
      _FilterEntry(
        'Turnos',
        Icons.work_history,
        Colors.teal,
        _filterTurnos,
        (v) => setState(() => _filterTurnos = v),
      ),
    ];

    final hiddenCount = items.where((e) => !e.active).length;

    return PopupMenuButton<int>(
      tooltip: 'Filtros activos',
      child: Padding(
        padding: const EdgeInsets.only(top: 4, left: 2),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            const Icon(Icons.more_vert, color: Colors.black54),
            if (hiddenCount > 0)
              Positioned(
                top: -4,
                right: -4,
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: const BoxDecoration(
                    color: Colors.redAccent,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      '$hiddenCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        height: 1.0,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      onSelected: (idx) {
        items[idx].toggle(!items[idx].active);
      },
      itemBuilder: (_) => items.asMap().entries.map((e) {
        final idx = e.key;
        final entry = e.value;
        return PopupMenuItem<int>(
          value: idx,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: entry.color.withOpacity(entry.active ? 0.15 : 0.06),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: entry.color.withOpacity(entry.active ? 0.6 : 0.2),
                    width: 1.5,
                  ),
                ),
                child: Icon(
                  entry.icon,
                  size: 15,
                  color: entry.active ? entry.color : Colors.grey.shade400,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  entry.label,
                  style: TextStyle(
                    fontSize: 14,
                    color: entry.active ? Colors.black87 : Colors.grey.shade400,
                    fontWeight: entry.active
                        ? FontWeight.w500
                        : FontWeight.normal,
                  ),
                ),
              ),
              Icon(
                entry.active ? Icons.check_circle : Icons.remove_circle_outline,
                size: 18,
                color: entry.active ? Colors.green : Colors.grey.shade300,
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildBgPopup() {
    return PopupMenuButton<String>(
      tooltip: 'Fondo',
      icon: const Icon(Icons.format_color_fill, color: Colors.black87),
      onSelected: (v) {
        setState(() => _selectedBgName = v);
        _saveSettings();
      },
      itemBuilder: (_) => _bgOptions.keys
          .map(
            (name) => PopupMenuItem<String>(
              value: name,
              child: Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: _bgOptions[name],
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.black12),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(name, overflow: TextOverflow.ellipsis)),
                ],
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _buildDesignPopup() {
    return PopupMenuButton<String>(
      tooltip: 'Diseño',
      icon: const Icon(Icons.view_quilt, color: Colors.black87),
      onSelected: (v) {
        setState(() => _selectedDesign = v);
        _saveSettings();
      },
      itemBuilder: (_) => _designOptions
          .map((name) => PopupMenuItem<String>(value: name, child: Text(name)))
          .toList(),
    );
  }

  Widget _buildCompactToggle() {
    return IconButton(
      tooltip: _compactMode ? 'Salir modo compacto' : 'Modo compacto',
      icon: Icon(
        _compactMode ? Icons.grid_view : Icons.view_week,
        color: Colors.black87,
      ),
      onPressed: () {
        setState(() => _compactMode = !_compactMode);
        _saveSettings();
      },
    );
  }

  // ── Celda ──────────────────────────────────────────────────────────────────

  Widget _buildCell(
    DateTime date, {
    required double width,
    required double height,
    required bool compact,
  }) {
    final isInMonth = date.month == _focusedMonth.month;
    final events = _eventsForDay(date);
    final shifts = _shiftsForDay(date);
    final sharedShifts = _sharedShiftsForDay(date);
    final now = DateTime.now();
    final isToday =
        now.year == date.year && now.month == date.month && now.day == date.day;
    final isSelected =
        _selectedDay != null &&
        _selectedDay!.year == date.year &&
        _selectedDay!.month == date.month &&
        _selectedDay!.day == date.day;

    final utcKey = DateTime.utc(date.year, date.month, date.day);
    final bool isPending = _pendingDays.contains(utcKey);

    void openDay() {
      if (_assigningShift != null) {
        if (!isInMonth) return;
        setState(() {
          if (isPending) {
            _pendingDays.remove(utcKey);
          } else {
            _pendingDays.add(utcKey);
          }
        });
        return;
      }
      setState(() => _selectedDay = date);
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => DayView(date: date)))
          .then((_) => _loadMonth(_focusedMonth));
    }

    // ── Overlay visual de asignación ───────────────────────────────────────
    Widget assignOverlay() {
      if (_assigningShift == null || !isInMonth) return const SizedBox.shrink();
      return Positioned.fill(
        child: Container(
          margin: compact ? const EdgeInsets.all(4) : const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: isPending
                ? _assigningShift!.color.withOpacity(0.22)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(compact ? 6 : 8),
            border: Border.all(
              color: isPending
                  ? _assigningShift!.color
                  : Colors.grey.withOpacity(0.4),
              width: isPending ? 2.0 : 1.0,
            ),
          ),
          child: isPending
              ? Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Icon(
                      Icons.check_circle,
                      size: compact ? 10 : 14,
                      color: _assigningShift!.color,
                    ),
                  ),
                )
              : null,
        ),
      );
    }

    // ── Modo compacto ──────────────────────────────────────────────────────
    //
    // La celda ahora tiene un mínimo de _kMinCompactCellH (72 px), así que
    // hay espacio suficiente para mostrar todos los elementos sin restricción
    // de prioridad. ClipRect evita cualquier desbordamiento visual residual.
    //
    if (compact) {
      final ShiftModel? firstShift = shifts.isNotEmpty ? shifts.first : null;
      final SharedShiftInfo? firstShared = sharedShifts.isNotEmpty
          ? sharedShifts.first
          : null;

      final Color? dotColor = events.isNotEmpty ? events.first.color : null;
      final int extra = events.length > 1 ? events.length - 1 : 0;

      return GestureDetector(
        onTap: isInMonth ? openDay : null,
        child: Stack(
          children: [
            ClipRect(
              child: Container(
                margin: const EdgeInsets.all(4),
                decoration: _cellDecoration(
                  isSelected: isSelected,
                  isToday: isToday,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    // Número del día
                    Text(
                      '${date.day}',
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: isInMonth ? null : Colors.grey[400],
                        height: 1.0,
                      ),
                    ),
                    // Badge de turno propio
                    if (firstShift != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: _shiftBadge(firstShift, compact: true),
                      ),
                    // Badge de turno compartido (si no hay propio)
                    if (firstShift == null && firstShared != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: _sharedShiftBadge(firstShared, compact: true),
                      ),
                    // Punto o emoji de evento
                    if (dotColor != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Builder(
                          builder: (_) {
                            final friend = _friendForEvent(events.first);
                            if (friend != null) {
                              return Text(
                                friend.logo,
                                style: const TextStyle(fontSize: 9, height: 1),
                              );
                            }
                            return Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: dotColor,
                                shape: BoxShape.circle,
                              ),
                            );
                          },
                        ),
                      ),
                    // Contador "+N"
                    if (extra > 0)
                      Text(
                        '+$extra',
                        style: TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.w700,
                          color:
                              Theme.of(context).textTheme.bodyMedium?.color ??
                              Colors.black,
                          height: 1.0,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            assignOverlay(),
          ],
        ),
      );
    }

    // ── Modo detallado ─────────────────────────────────────────────────────
    const int maxEventsConsidered = 6;

    return SizedBox(
      height: height,
      child: GestureDetector(
        onTap: isInMonth ? openDay : null,
        child: Stack(
          children: [
            Container(
              margin: const EdgeInsets.all(6),
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
              decoration: _cellDecoration(
                isSelected: isSelected,
                isToday: isToday,
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final double eventsAreaHeight = math.max(
                    0.0,
                    constraints.maxHeight - 40.0,
                  );

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            '${date.day}',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: isInMonth ? null : Colors.grey[400],
                            ),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: shifts.isEmpty
                                ? const SizedBox.shrink()
                                : SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: Row(
                                      children: shifts
                                          .map(
                                            (s) =>
                                                _shiftBadge(s, compact: false),
                                          )
                                          .toList(),
                                    ),
                                  ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      SizedBox(
                        height: eventsAreaHeight,
                        child: (events.isEmpty && sharedShifts.isEmpty)
                            ? const SizedBox.shrink()
                            : SingleChildScrollView(
                                physics: const ClampingScrollPhysics(),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    for (
                                      var i = 0;
                                      i <
                                          math.min(
                                            events.length,
                                            maxEventsConsidered,
                                          );
                                      i++
                                    )
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 3,
                                        ),
                                        child: Builder(
                                          builder: (ctx) {
                                            final ev = events[i];
                                            final friend = _friendForEvent(ev);
                                            final isShared = friend != null;
                                            return Container(
                                              decoration: isShared
                                                  ? BoxDecoration(
                                                      border: Border.all(
                                                        color:
                                                            Colors.red.shade400,
                                                        width: 1,
                                                      ),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            4,
                                                          ),
                                                    )
                                                  : null,
                                              padding: isShared
                                                  ? const EdgeInsets.symmetric(
                                                      horizontal: 3,
                                                      vertical: 1,
                                                    )
                                                  : EdgeInsets.zero,
                                              child: Row(
                                                children: [
                                                  Container(
                                                    width: 8,
                                                    height: 8,
                                                    decoration: BoxDecoration(
                                                      color: ev.color,
                                                      shape: BoxShape.circle,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 4),
                                                  if (isShared) ...[
                                                    Text(
                                                      friend!.logo,
                                                      style: const TextStyle(
                                                        fontSize: 10,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 2),
                                                  ] else ...[
                                                    Text(
                                                      ev.icon,
                                                      style: const TextStyle(
                                                        fontSize: 11,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 4),
                                                  ],
                                                  Expanded(
                                                    child: Text(
                                                      ev.title,
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                        color: isInMonth
                                                            ? null
                                                            : Colors.grey[400],
                                                        fontStyle: isShared
                                                            ? FontStyle.italic
                                                            : FontStyle.normal,
                                                      ),
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      maxLines: 1,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                    ...sharedShifts
                                        .take(maxEventsConsidered)
                                        .map(
                                          (s) => Padding(
                                            padding: const EdgeInsets.only(
                                              bottom: 3,
                                            ),
                                            child: _sharedShiftBadge(s),
                                          ),
                                        ),
                                  ],
                                ),
                              ),
                      ),
                    ],
                  );
                },
              ),
            ),
            assignOverlay(),
          ],
        ),
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!_settingsLoaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final firstOfMonth = DateTime(_focusedMonth.year, _focusedMonth.month, 1);
    final lastOfMonth = DateTime(
      _focusedMonth.year,
      _focusedMonth.month + 1,
      0,
    );
    final int leadingEmpty = (firstOfMonth.weekday - 1) % 7;
    final int totalDays = leadingEmpty + lastOfMonth.day;
    final int rows = (totalDays / 7).ceil();
    final int effectiveRows = _compactMode ? 6 : rows;
    final int totalCells = effectiveRows * 7;

    final List<DateTime> cells = List.generate(totalCells, (i) {
      return DateTime(
        _focusedMonth.year,
        _focusedMonth.month,
        i - leadingEmpty + 1,
      );
    });

    const double desiredCellWidth = 140.0;
    const double cellMargin = 6.0;
    final double realCellWidth = desiredCellWidth + cellMargin * 2;
    final double totalWidth = realCellWidth * 7;
    const int maxEventsConsidered = 6;
    const double baseCellHeight = 64.0;
    const double perEventHeight = 22.0;
    const labels = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];

    final titleRow = Row(
      children: [
        Expanded(
          child: Text(
            _monthLabel(_focusedMonth),
            style: const TextStyle(color: Colors.black87),
          ),
        ),
        if (_eventsLoading)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        _buildBgPopup(),
        const SizedBox(width: 4),
        _buildDesignPopup(),
        _buildCompactToggle(),
        IconButton(
          icon: const Icon(Icons.chevron_left, color: Colors.black87),
          onPressed: _prevMonthAction,
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right, color: Colors.black87),
          onPressed: _nextMonthAction,
        ),
      ],
    );

    Widget buildCalendarTable(double cellW, double cellH) {
      return Table(
        defaultColumnWidth: FixedColumnWidth(cellW),
        border: TableBorder.symmetric(outside: BorderSide.none),
        children: List.generate(effectiveRows, (rowIndex) {
          final start = rowIndex * 7;
          final rowCells = cells.sublist(start, start + 7);
          final maxEventsInRow = rowCells
              .map(
                (d) => _eventsForDay(d).length + _sharedShiftsForDay(d).length,
              )
              .fold<int>(0, (prev, cur) => math.max(prev, cur));
          final hasShifts = rowCells.any((d) => _shiftsForDay(d).isNotEmpty);
          final considered = math.min(maxEventsInRow, maxEventsConsidered);
          final double shiftRow = hasShifts ? 22.0 : 0.0;
          final double rowHeight = _compactMode
              ? cellH
              : baseCellHeight + shiftRow + considered * perEventHeight;

          return TableRow(
            children: rowCells
                .map(
                  (date) => _buildCell(
                    date,
                    width: cellW,
                    height: rowHeight,
                    compact: _compactMode,
                  ),
                )
                .toList(),
          );
        }),
      );
    }

    return Scaffold(
      appBar: AppBar(
        iconTheme: const IconThemeData(color: Colors.black87),
        actionsIconTheme: const IconThemeData(color: Colors.black87),
        titleTextStyle: const TextStyle(
          color: Colors.black87,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        elevation: 2,
        title: titleRow,
        actions: const [],
      ),
      body: SafeArea(
        child: Container(
          color: _backgroundColor,
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              children: [
                // ── Filtros ──────────────────────────────────────────────────
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          if (_filterTrabajo)
                            FilterChip(
                              label: const Text('Trabajo'),
                              selected: true,
                              onSelected: (v) {
                                setState(() => _filterTrabajo = v);
                                _saveSettings();
                              },
                            ),
                          if (_filterEventos)
                            FilterChip(
                              label: const Text('Eventos'),
                              selected: true,
                              onSelected: (v) {
                                setState(() => _filterEventos = v);
                                _saveSettings();
                              },
                            ),
                          if (_filterCitas)
                            FilterChip(
                              label: const Text('Citas'),
                              selected: true,
                              onSelected: (v) {
                                setState(() => _filterCitas = v);
                                _saveSettings();
                              },
                            ),
                          if (_filterRecordatorios)
                            FilterChip(
                              label: const Text('Recordatorios'),
                              selected: true,
                              onSelected: (v) {
                                setState(() => _filterRecordatorios = v);
                                _saveSettings();
                              },
                            ),
                          if (_filterBebe)
                            FilterChip(
                              label: const Text('Bebé'),
                              selected: true,
                              onSelected: (v) {
                                setState(() => _filterBebe = v);
                                _saveSettings();
                              },
                            ),
                          if (_filterPeriodo)
                            FilterChip(
                              label: const Text('Período'),
                              selected: true,
                              onSelected: (v) {
                                setState(() => _filterPeriodo = v);
                                _saveSettings();
                              },
                            ),
                          if (_filterTurnos)
                            FilterChip(
                              avatar: const Icon(Icons.work_outline, size: 14),
                              label: const Text('Turnos'),
                              selected: true,
                              onSelected: (v) =>
                                  setState(() => _filterTurnos = v),
                            ),
                        ],
                      ),
                    ),
                    // ── Controles derecha ────────────────────────────────────
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildFilterSummaryMenu(),
                        Tooltip(
                          message: 'Compartir',
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: _openShareDialog,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              child: const Icon(
                                Icons.share_outlined,
                                size: 20,
                                color: Colors.black54,
                              ),
                            ),
                          ),
                        ),
                        _buildAssignShiftButton(),
                        _buildFriendFilterButton(),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // ── Barra de confirmación de asignación ──────────────────────
                if (_assigningShift != null)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: _assigningShift!.color.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _assigningShift!.color.withOpacity(0.5),
                        width: 1.5,
                      ),
                    ),
                    child: _loadingAssignment
                        ? const Center(
                            child: SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : Row(
                            children: [
                              Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: _assigningShift!.color,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Asignando: ${_assigningShift!.name}  •  ${_pendingDays.length} días',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: _assigningShift!.color.withOpacity(
                                      0.9,
                                    ),
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              TextButton(
                                onPressed: _cancelShiftAssignment,
                                style: TextButton.styleFrom(
                                  foregroundColor: Colors.grey.shade600,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                  ),
                                  minimumSize: Size.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: const Text(
                                  'Cancelar',
                                  style: TextStyle(fontSize: 12),
                                ),
                              ),
                              const SizedBox(width: 4),
                              ElevatedButton.icon(
                                onPressed: _confirmShiftAssignment,
                                icon: const Icon(Icons.check, size: 14),
                                label: const Text(
                                  'Confirmar',
                                  style: TextStyle(fontSize: 12),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _assigningShift!.color,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  minimumSize: Size.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                            ],
                          ),
                  ),

                // ── Calendario ───────────────────────────────────────────────
                Expanded(
                  child: _compactMode
                      ? LayoutBuilder(
                          builder: (context, constraints) {
                            const double labelsHeight = 32.0;
                            const double gapBetween = 6.0;
                            const double cellMarginCompact = 4.0;
                            final double availableHeight =
                                constraints.maxHeight -
                                labelsHeight -
                                gapBetween;
                            final double totalVertMargins =
                                cellMarginCompact * 2 * 6;

                            // La celda usa el mayor entre el espacio disponible
                            // dividido entre 6 filas y el mínimo garantizado.
                            // Si las celdas crecen más que la pantalla, el grid
                            // se vuelve scrollable verticalmente.
                            final double compactCellH = math.max(
                              ((availableHeight - totalVertMargins) / 6.0) -
                                  1.0,
                              _kMinCompactCellH,
                            );
                            final double compactCellW =
                                (constraints.maxWidth / 7.0).clamp(
                                  1.0,
                                  double.infinity,
                                );
                            final double gridH =
                                (compactCellH * 6) + totalVertMargins;

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Cabecera de días fija
                                SizedBox(
                                  height: labelsHeight,
                                  child: Row(
                                    children: List.generate(
                                      7,
                                      (i) => SizedBox(
                                        width: compactCellW,
                                        child: Center(
                                          child: Text(
                                            labels[i],
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: Colors.black87,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                SizedBox(height: gapBetween),
                                // Grid scrollable si la altura supera la pantalla
                                Expanded(
                                  child: SingleChildScrollView(
                                    physics: gridH > availableHeight
                                        ? const ClampingScrollPhysics()
                                        : const NeverScrollableScrollPhysics(),
                                    child: SizedBox(
                                      height: gridH,
                                      width: constraints.maxWidth,
                                      child: GridView.count(
                                        physics:
                                            const NeverScrollableScrollPhysics(),
                                        crossAxisCount: 7,
                                        childAspectRatio:
                                            compactCellW / compactCellH,
                                        mainAxisSpacing: 0,
                                        crossAxisSpacing: 0,
                                        padding: EdgeInsets.zero,
                                        shrinkWrap: true,
                                        children: List.generate(
                                          totalCells,
                                          (i) => _buildCell(
                                            cells[i],
                                            width: compactCellW,
                                            height: compactCellH,
                                            compact: true,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        )
                      : SingleChildScrollView(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            controller: _horizontalController,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(minWidth: totalWidth),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(
                                    height: 32,
                                    child: Row(
                                      children: List.generate(
                                        7,
                                        (i) => SizedBox(
                                          width: realCellWidth,
                                          child: Center(
                                            child: Text(
                                              labels[i],
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color: Colors.black87,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  buildCalendarTable(
                                    realCellWidth,
                                    baseCellHeight,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Datos de un filtro para el menú de 3 puntos ───────────────────────────────

class _FilterEntry {
  final String label;
  final IconData icon;
  final Color color;
  final bool active;
  final void Function(bool) toggle;

  const _FilterEntry(
    this.label,
    this.icon,
    this.color,
    this.active,
    this.toggle,
  );
}

// ── Bottom sheet: filtro de amigos ────────────────────────────────────────────

class _FriendFilterSheet extends StatefulWidget {
  final List<FriendModel> friends;
  final Set<String> hiddenUids;
  final ValueChanged<Set<String>> onChanged;

  const _FriendFilterSheet({
    required this.friends,
    required this.hiddenUids,
    required this.onChanged,
    Key? key,
  }) : super(key: key);

  @override
  State<_FriendFilterSheet> createState() => _FriendFilterSheetState();
}

class _FriendFilterSheetState extends State<_FriendFilterSheet> {
  late Set<String> _hidden;

  @override
  void initState() {
    super.initState();
    _hidden = Set<String>.from(widget.hiddenUids);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              const Icon(Icons.people_outlined, size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Eventos compartidos',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
              TextButton(
                onPressed: () {
                  setState(() => _hidden.clear());
                  widget.onChanged(_hidden);
                },
                child: const Text('Ver todos'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Pulsa para mostrar u ocultar los eventos de cada amigo',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
          ),
          const SizedBox(height: 12),
          ...widget.friends.map((friend) {
            final uid = friend.firebaseUid ?? '';
            final visible = !_hidden.contains(uid);
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: visible ? Colors.red.shade50 : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: visible ? Colors.red.shade300 : Colors.grey.shade300,
                    width: 1.5,
                  ),
                ),
                child: Center(
                  child: Text(
                    friend.logo,
                    style: const TextStyle(fontSize: 22),
                  ),
                ),
              ),
              title: Text(
                friend.displayName,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: visible ? Colors.black87 : Colors.grey.shade400,
                ),
              ),
              subtitle: Text(
                friend.email,
                style: TextStyle(
                  fontSize: 12,
                  color: visible ? Colors.grey.shade500 : Colors.grey.shade300,
                ),
              ),
              trailing: Switch(
                value: visible,
                activeColor: Colors.red.shade400,
                onChanged: (_) {
                  setState(() {
                    if (_hidden.contains(uid))
                      _hidden.remove(uid);
                    else
                      _hidden.add(uid);
                  });
                  widget.onChanged(Set<String>.from(_hidden));
                },
              ),
            );
          }).toList(),
        ],
      ),
    );
  }
}

// ── Bottom sheet: selección de turno ─────────────────────────────────────────

class _ShiftPickerSheet extends StatelessWidget {
  final List<ShiftModel> shifts;
  final ValueChanged<ShiftModel> onSelected;

  const _ShiftPickerSheet({
    required this.shifts,
    required this.onSelected,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    const double headerHeight = 110.0;
    final double listHeight = shifts.length * 72.0;
    final double bottomPadding = MediaQuery.of(context).padding.bottom + 32.0;
    final double maxSheetHeight = MediaQuery.of(context).size.height * 0.9;
    final double sheetHeight = (headerHeight + listHeight + bottomPadding)
        .clamp(0, maxSheetHeight);

    return SizedBox(
      height: sheetHeight,
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Row(
                    children: [
                      Icon(Icons.edit_calendar_outlined, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'Asignar turno al mes',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Elige un turno y pulsa los días del mes para marcarlo',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
              ),
            ),
            Flexible(
              child: shifts.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text(
                          'No tienes turnos creados todavía.',
                          style: TextStyle(color: Colors.grey.shade400),
                        ),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      padding: EdgeInsets.fromLTRB(
                        20,
                        0,
                        20,
                        MediaQuery.of(context).padding.bottom + 32,
                      ),
                      itemCount: shifts.length,
                      itemBuilder: (_, index) {
                        final shift = shifts[index];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: shift.color.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: shift.color.withOpacity(0.5),
                                width: 1.5,
                              ),
                            ),
                            child: Center(
                              child: Icon(
                                Icons.work_history,
                                color: shift.color,
                                size: 22,
                              ),
                            ),
                          ),
                          title: Text(
                            shift.name,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            '${shift.from.format(context)} – ${shift.to.format(context)}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade500,
                            ),
                          ),
                          trailing: Icon(
                            Icons.chevron_right,
                            color: shift.color,
                          ),
                          onTap: () => onSelected(shift),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
