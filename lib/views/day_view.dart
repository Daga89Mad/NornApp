// lib/views/day_view.dart

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../models/event_item.dart';
import '../models/checklist_item.dart';
import '../core/event_repository.dart';
import '../core/checklist_repository.dart';
import '../models/shift_model.dart';
import '../core/shift_repository.dart';
import '../core/shift_assignment_repository.dart';
import '../models/friend_model.dart';
import '../core/friend_repository.dart';
import 'checklist_detail_page.dart';
import '../core/fun_content_repository.dart';
import 'fun_day_sheet.dart';

class DayView extends StatefulWidget {
  final DateTime date;
  const DayView({Key? key, required this.date}) : super(key: key);

  @override
  State<DayView> createState() => _DayViewState();
}

class _DayViewState extends State<DayView> {
  List<EventItem> _events = [];
  List<ShiftModel> _allShifts = [];
  Set<String> _activeShiftIds = {};
  List<SharedShiftInfo> _sharedShifts = [];
  List<FriendModel> _cachedFriends = [];
  bool _isLoading = true;

  static const double hourHeight = 80.0;
  static const double leftColumnWidth = 70.0;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    if (mounted) setState(() => _isLoading = true);

    try {
      // Seeds no críticos: si fallan, no bloquean la carga de eventos
      try {
        await FunContentRepository.instance.seedIfEmpty();
      } catch (e) {
        debugPrint('⚠️ seedIfEmpty error (ignorado): $e');
      }

      try {
        await ShiftRepository.instance.seedDefaults();
      } catch (e) {
        debugPrint('⚠️ seedDefaults error (ignorado): $e');
      }

      // Carga paralela de datos principales con timeout de seguridad
      final results =
          await Future.wait([
            EventRepository.instance.getEventsForDay(widget.date),
            ShiftRepository.instance.getAll(),
            ShiftAssignmentRepository.instance.getAssignedShiftIds(widget.date),
          ]).timeout(
            const Duration(seconds: 10),
            onTimeout: () => [<EventItem>[], <ShiftModel>[], <String>{}],
          );

      // Datos secundarios también protegidos individualmente
      List<SharedShiftInfo> sharedShifts = [];
      try {
        sharedShifts = await ShiftAssignmentRepository.instance
            .getSharedShiftsForDay(widget.date);
      } catch (e) {
        debugPrint('⚠️ getSharedShiftsForDay error (ignorado): $e');
      }

      List<FriendModel> friends = [];
      try {
        friends = await FriendRepository.instance.getAll();
      } catch (e) {
        debugPrint('⚠️ getAll friends error (ignorado): $e');
      }

      if (mounted) {
        setState(() {
          _events = results[0] as List<EventItem>;
          _allShifts = results[1] as List<ShiftModel>;
          _activeShiftIds = results[2] as Set<String>;
          _sharedShifts = sharedShifts;
          _cachedFriends = friends;
        });
      }
    } catch (e) {
      debugPrint('❌ Error cargando día: $e');
    } finally {
      // Garantizado: siempre se quita el spinner
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Fun day sheet ──────────────────────────────────────────────────────────

  void _openFunSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const FunDaySheet(),
    );
  }

  double _timeOfDayToTop(TimeOfDay t) =>
      (t.hour * 60 + t.minute) / 60.0 * hourHeight;

  // ── Toggle turno ───────────────────────────────────────────────────────────

  Future<void> _toggleShift(ShiftModel shift) async {
    if (shift.id == null) return;
    final nowActive = await ShiftAssignmentRepository.instance.toggle(
      shift.id!,
      widget.date,
    );
    if (mounted) {
      setState(() {
        if (nowActive) {
          _activeShiftIds.add(shift.id!);
        } else {
          _activeShiftIds.remove(shift.id!);
        }
      });
    }
  }

  // ── Añadir evento ──────────────────────────────────────────────────────────

  Future<void> _openAddEventDialog() async {
    final result = await showDialog<Map<String, dynamic>?>(
      context: context,
      builder: (_) => const AddEventDialog(),
    );
    if (result == null) return;
    await _saveEventFromResult(result, existingEvent: null);
  }

  // ── Editar evento ──────────────────────────────────────────────────────────

  Future<void> _editEvent(EventItem ev, int idx) async {
    List<String> existingItems = [];
    if (ev.tipo == Tipo.Checklist && ev.id != null) {
      try {
        final items = await ChecklistRepository.instance.getItemsForEvent(
          ev.id!,
        );
        existingItems = items.map((i) => i.text).toList();
      } catch (_) {}
    }
    if (!mounted) return;

    final result = await showDialog<Map<String, dynamic>?>(
      context: context,
      builder: (_) => AddEventDialog(
        initialEvent: ev,
        initialChecklistItems: existingItems,
      ),
    );
    if (result == null) return;

    final saved = await _saveEventFromResult(result, existingEvent: ev);
    if (saved != null && mounted) setState(() => _events[idx] = saved);
  }

  Future<EventItem?> _saveEventFromResult(
    Map<String, dynamic> result, {
    required EventItem? existingEvent,
  }) async {
    final categoryStr = result['category'] as String? ?? 'Eventos';
    final category = EventRepository.categoryFromString(categoryStr);
    final tipo = (result['tipo'] as Tipo?) ?? Tipo.Otros;
    final currentUser = FirebaseAuth.instance.currentUser;
    final creator =
        existingEvent?.creator ??
        currentUser?.email ??
        currentUser?.uid ??
        'yo';

    final newEvent = EventItem(
      id: existingEvent?.id,
      category: category,
      tipo: tipo,
      title: result['title'] as String,
      description: (result['description'] as String?) ?? '',
      icon: EventRepository.iconForCategory(category),
      creator: creator,
      users: existingEvent?.users ?? [creator],
      from: result['start'] as TimeOfDay,
      to: result['end'] as TimeOfDay,
      color: EventRepository.colorForCategory(category),
      hasAlarm: (result['hasAlarm'] as bool?) ?? false,
      alarmAt: result['alarmAt'] as DateTime?,
      hasNotification: (result['hasNotif'] as bool?) ?? false,
      notificationAt: result['notifAt'] as DateTime?,
      soloParaMi: (result['soloParaMi'] as bool?) ?? false,
    );

    try {
      final saved = await EventRepository.instance.save(newEvent, widget.date);

      if (saved.id != null && tipo == Tipo.Checklist) {
        final items = (result['checklistItems'] as List<String>?) ?? [];
        await ChecklistRepository.instance.saveAll(saved.id!, items);
      } else if (saved.id != null &&
          existingEvent?.tipo == Tipo.Checklist &&
          tipo != Tipo.Checklist) {
        await ChecklistRepository.instance.deleteAllForEvent(saved.id!);
      }

      if (existingEvent == null && mounted) {
        setState(() => _events.add(saved));
      }
      return saved;
    } catch (e) {
      debugPrint('Error guardando evento: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error al guardar: $e')));
      }
      return null;
    }
  }

  // ── Eliminar ───────────────────────────────────────────────────────────────

  Future<void> _deleteEvent(int idx) async {
    final event = _events[idx];
    if (event.id == null) return;

    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Borrar evento'),
        content: Text('¿Borrar "${event.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Borrar'),
          ),
        ],
      ),
    );
    if (shouldDelete != true) return;

    try {
      if (event.tipo == Tipo.Checklist) {
        await ChecklistRepository.instance.deleteAllForEvent(event.id!);
      }
      await EventRepository.instance.delete(event.id!);
      if (mounted) setState(() => _events.removeAt(idx));
    } catch (e) {
      debugPrint('Error eliminando evento: $e');
    }
  }

  Future<void> _deleteAll() async {
    if (_events.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Borrar todos los eventos'),
        content: const Text(
          '¿Seguro que quieres borrar todos los eventos de este día?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Borrar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      for (final ev in _events) {
        if (ev.tipo == Tipo.Checklist && ev.id != null) {
          await ChecklistRepository.instance.deleteAllForEvent(ev.id!);
        }
      }
      await EventRepository.instance.deleteAllForDay(widget.date);
      if (mounted) setState(() => _events.clear());
    } catch (e) {
      debugPrint('Error eliminando todos: $e');
    }
  }

  // ── Detalle ────────────────────────────────────────────────────────────────

  void _showEventDetail(BuildContext context, EventItem ev, int idx) {
    if (ev.tipo == Tipo.Checklist) {
      Navigator.of(context)
          .push(
            MaterialPageRoute(
              builder: (_) => ChecklistDetailPage(event: ev, date: widget.date),
            ),
          )
          .then((result) async {
            if (result is Map) {
              final action = result['action'] as String?;
              if (action == 'deleted') {
                _loadAll();
              } else if (action == 'edit') {
                await _editEvent(ev, idx);
              } else {
                _loadAll();
              }
            } else {
              _loadAll();
            }
          });
      return;
    }

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text('${ev.icon} ${ev.title}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _detailRow(Icons.category_outlined, ev.category.name),
            _detailRow(Icons.label_outline, ev.tipo.name),
            const SizedBox(height: 4),
            _detailRow(
              Icons.access_time,
              '${ev.from.format(context)} — ${ev.to.format(context)}',
            ),
            _detailRow(Icons.person_outline, ev.creator),
            if (ev.soloParaMi) _detailRow(Icons.lock_outline, 'Solo para mí'),
            if (ev.hasAlarm && ev.alarmAt != null)
              _detailRow(Icons.alarm, 'Alarma: ${_fmtDateTime(ev.alarmAt!)}'),
            if (ev.hasNotification && ev.notificationAt != null)
              _detailRow(
                Icons.notifications_outlined,
                'Notif.: ${_fmtDateTime(ev.notificationAt!)}',
              ),
            if (ev.description.isNotEmpty) ...[
              const Divider(height: 16),
              Text(ev.description, style: const TextStyle(fontSize: 13)),
            ],
          ],
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.delete_outline, color: Colors.red),
            label: const Text('Borrar', style: TextStyle(color: Colors.red)),
            onPressed: () {
              Navigator.of(dialogCtx).pop();
              _deleteEvent(idx);
            },
          ),
          TextButton.icon(
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Editar'),
            onPressed: () {
              Navigator.of(dialogCtx).pop();
              _editEvent(ev, idx);
            },
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(IconData icon, String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey.shade600),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
      ],
    ),
  );

  String _fmtDateTime(DateTime dt) {
    final d =
        '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$d $h:$m';
  }

  // ── Tarjeta de evento ──────────────────────────────────────────────────────

  Widget _buildEventCard(int idx, EventItem ev) {
    final double top = _timeOfDayToTop(ev.from);
    final double bottom = _timeOfDayToTop(ev.to);
    final double cardH = (bottom - top).clamp(80.0, double.infinity) - 12;
    final isChecklist = ev.tipo == Tipo.Checklist;

    return Positioned(
      top: top + 6,
      left: leftColumnWidth + 12,
      right: 12,
      height: cardH,
      child: GestureDetector(
        onTap: () => _showEventDetail(context, ev, idx),
        onLongPress: () => _deleteEvent(idx),
        child: Card(
          color: ev.color.withOpacity(0.15),
          elevation: 2,
          clipBehavior: Clip.hardEdge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: ev.color, width: 1.5),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: FittedBox(
                        fit: BoxFit.contain,
                        child: Text(ev.icon),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        ev.title,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                    if (isChecklist)
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Icon(Icons.checklist, size: 16, color: ev.color),
                      ),
                    if (ev.hasAlarm)
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Icon(Icons.alarm, size: 14, color: ev.color),
                      ),
                    if (ev.hasNotification)
                      Padding(
                        padding: const EdgeInsets.only(left: 2),
                        child: Icon(
                          Icons.notifications,
                          size: 14,
                          color: ev.color,
                        ),
                      ),
                  ],
                ),
                Text(
                  '${ev.from.format(context)} - ${ev.to.format(context)}',
                  style: const TextStyle(fontSize: 10, color: Colors.black54),
                ),
                if (ev.description.isNotEmpty)
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        ev.description,
                        style: const TextStyle(fontSize: 11),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
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

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final dateLabel =
        '${widget.date.day}/${widget.date.month}/${widget.date.year}';
    final double totalHeight = 24 * hourHeight;

    return Scaffold(
      appBar: AppBar(title: Text('Día - $dateLabel')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                children: [
                  // ── Cabecera: título + botones fun / compartir ────────
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Eventos del $dateLabel',
                          style:
                              Theme.of(context).textTheme.titleLarge ??
                              const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ),
                      // Botón 😄 fun
                      Tooltip(
                        message: '¿Qué quieres hoy?',
                        child: InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: _openFunSheet,
                          child: const Padding(
                            padding: EdgeInsets.all(6),
                            child: Text('😄', style: TextStyle(fontSize: 22)),
                          ),
                        ),
                      ),
                      // Botón compartir (placeholder)
                      Tooltip(
                        message: 'Compartir día (próximamente)',
                        child: InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Compartir día — próximamente'),
                                duration: Duration(seconds: 2),
                              ),
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(6),
                            child: Icon(
                              Icons.share_outlined,
                              size: 22,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      ElevatedButton.icon(
                        onPressed: _openAddEventDialog,
                        icon: const Icon(Icons.add),
                        label: const Text('Añadir evento'),
                      ),
                      ElevatedButton.icon(
                        onPressed: _deleteAll,
                        icon: const Icon(Icons.delete),
                        label: const Text('Borrar todos'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // ── Turnos del día ─────────────────────────────────────────
                  if (_allShifts.isNotEmpty) ...[
                    const Text(
                      'Turnos del día',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      height: 44,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _allShifts.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (_, i) {
                          final shift = _allShifts[i];
                          final active =
                              shift.id != null &&
                              _activeShiftIds.contains(shift.id);
                          final c = shift.color;
                          return GestureDetector(
                            onTap: () => _toggleShift(shift),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                gradient: active
                                    ? LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors: [
                                          Color.lerp(Colors.white, c, 0.65)!,
                                          c,
                                        ],
                                      )
                                    : null,
                                color: active ? null : Colors.grey.shade200,
                                boxShadow: [
                                  BoxShadow(
                                    color: active
                                        ? c.withOpacity(0.45)
                                        : Colors.black.withOpacity(0.08),
                                    offset: const Offset(0, 2),
                                    blurRadius: 4,
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    active
                                        ? Icons.check_circle
                                        : Icons.radio_button_unchecked,
                                    size: 14,
                                    color: active
                                        ? Colors.white
                                        : Colors.grey.shade500,
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    shift.name,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: active
                                          ? Colors.white
                                          : Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],

                  // ── Línea de tiempo ────────────────────────────────────────
                  Expanded(
                    child: SingleChildScrollView(
                      child: SizedBox(
                        height: totalHeight,
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: Column(
                                children: List.generate(24, (hour) {
                                  return SizedBox(
                                    height: hourHeight,
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        SizedBox(
                                          width: leftColumnWidth,
                                          child: Padding(
                                            padding: const EdgeInsets.only(
                                              top: 6.0,
                                            ),
                                            child: Text(
                                              '${hour.toString().padLeft(2, '0')}:00',
                                              style: const TextStyle(
                                                color: Colors.grey,
                                              ),
                                            ),
                                          ),
                                        ),
                                        const VerticalDivider(width: 1),
                                        Expanded(
                                          child: Container(
                                            decoration: BoxDecoration(
                                              border: Border(
                                                bottom: BorderSide(
                                                  color: Colors.grey.shade300,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }),
                              ),
                            ),
                            ..._events.asMap().entries.map(
                              (entry) =>
                                  _buildEventCard(entry.key, entry.value),
                            ),
                            // Turnos compartidos de amigos en el timeline
                            ..._sharedShifts.map(
                              (s) => _buildSharedShiftCard(s),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  // ── Tarjeta de turno compartido en el timeline ────────────────────────────

  Widget _buildSharedShiftCard(SharedShiftInfo shift) {
    final top = _timeOfDayToTop(shift.from);
    final rawBot = _timeOfDayToTop(shift.to);
    final bottom = rawBot > top ? rawBot : top + 80.0;
    final height = (bottom - top).clamp(48.0, double.infinity);
    final c = shift.color;

    String friendLogo = '👤';
    for (final f in _cachedFriends) {
      if (f.firebaseUid == shift.ownerUid) {
        friendLogo = f.logo;
        break;
      }
    }

    return Positioned(
      top: top + 4,
      left: leftColumnWidth + 4,
      right: 4,
      height: height - 8,
      child: Container(
        decoration: BoxDecoration(
          color: c.withOpacity(0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.red.shade400, width: 1.5),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            Text(friendLogo, style: const TextStyle(fontSize: 16)),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    shift.name,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: c,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '${_fmt(shift.from)} - ${_fmt(shift.to)}',
                    style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

// ── AddEventDialog ─────────────────────────────────────────────────────────────

class AddEventDialog extends StatefulWidget {
  final EventItem? initialEvent;
  final List<String> initialChecklistItems;

  const AddEventDialog({
    Key? key,
    this.initialEvent,
    this.initialChecklistItems = const [],
  }) : super(key: key);

  @override
  State<AddEventDialog> createState() => _AddEventDialogState();
}

class _AddEventDialogState extends State<AddEventDialog> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descController = TextEditingController();
  final TextEditingController _itemController = TextEditingController();

  late String _category;
  late Tipo _tipo;
  late TimeOfDay _start;
  late TimeOfDay _end;
  late List<String> _checklistItems;

  // ── Alarma / Notificación / SoloParaMi ────────────────────────────────────
  bool _hasAlarm = false;
  DateTime? _alarmDateTime;
  bool _hasNotification = false;
  DateTime? _notifDateTime;
  bool _soloParaMi = false;

  bool get _isEditing => widget.initialEvent != null;

  static const Map<String, List<Tipo>> _tiposPorCategoria = {
    'Trabajo': [
      Tipo.Horario,
      Tipo.Reunion,
      Tipo.Entrega,
      Tipo.Checklist,
      Tipo.Otros,
    ],
    'Eventos': [
      Tipo.Cumpleanos,
      Tipo.Aniversario,
      Tipo.Boda,
      Tipo.Comunion,
      Tipo.Bautizo,
      Tipo.Despedida,
      Tipo.Checklist,
      Tipo.Otros,
    ],
    'Citas': [Tipo.Horario, Tipo.Checklist, Tipo.Otros],
    'Recordatorios': [Tipo.Horario, Tipo.Checklist, Tipo.Otros],
    'Bebé': [Tipo.Horario, Tipo.Checklist, Tipo.Otros],
    'Período': [Tipo.Horario, Tipo.Otros],
  };

  List<Tipo> get _tiposActuales => _tiposPorCategoria[_category] ?? Tipo.values;

  @override
  void initState() {
    super.initState();
    final ev = widget.initialEvent;
    if (ev != null) {
      _titleController.text = ev.title;
      _descController.text = ev.description;
      _category = EventRepository.categoryToString(ev.category);
      _start = ev.from;
      _end = ev.to;
      final tipos = _tiposPorCategoria[_category] ?? Tipo.values;
      _tipo = tipos.contains(ev.tipo) ? ev.tipo : tipos.first;
      _checklistItems = List<String>.from(widget.initialChecklistItems);
      _hasAlarm = ev.hasAlarm;
      _alarmDateTime = ev.alarmAt;
      _hasNotification = ev.hasNotification;
      _notifDateTime = ev.notificationAt;
      _soloParaMi = ev.soloParaMi;
    } else {
      _category = 'Trabajo';
      _tipo = Tipo.Horario;
      _start = const TimeOfDay(hour: 9, minute: 0);
      _end = const TimeOfDay(hour: 10, minute: 0);
      _checklistItems = [];
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    _itemController.dispose();
    super.dispose();
  }

  String _tipoLabel(Tipo t) {
    switch (t) {
      case Tipo.Horario:
        return 'Horario';
      case Tipo.Reunion:
        return 'Reunión';
      case Tipo.Entrega:
        return 'Entrega';
      case Tipo.Cumpleanos:
        return 'Cumpleaños';
      case Tipo.Aniversario:
        return 'Aniversario';
      case Tipo.Boda:
        return 'Boda';
      case Tipo.Comunion:
        return 'Comunión';
      case Tipo.Bautizo:
        return 'Bautizo';
      case Tipo.Checklist:
        return 'Checklist';
      case Tipo.Despedida:
        return 'Despedida';
      case Tipo.Otros:
        return 'Otros';
    }
  }

  void _addChecklistItem() {
    final text = _itemController.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _checklistItems.add(text);
      _itemController.clear();
    });
  }

  Future<void> _pickStart() async {
    final t = await showTimePicker(context: context, initialTime: _start);
    if (t != null) {
      setState(() {
        _start = t;
        final sMin = _start.hour * 60 + _start.minute;
        final eMin = _end.hour * 60 + _end.minute;
        if (eMin <= sMin) {
          final ne = sMin + 30;
          _end = TimeOfDay(hour: (ne ~/ 60) % 24, minute: ne % 60);
        }
      });
    }
  }

  Future<void> _pickEnd() async {
    final t = await showTimePicker(context: context, initialTime: _end);
    if (t != null) {
      setState(() {
        _end = t;
        final sMin = _start.hour * 60 + _start.minute;
        final eMin = _end.hour * 60 + _end.minute;
        if (eMin <= sMin) {
          final ne = sMin + 30;
          _end = TimeOfDay(hour: (ne ~/ 60) % 24, minute: ne % 60);
        }
      });
    }
  }

  /// Abre un DatePicker + TimePicker encadenados y devuelve el DateTime.
  Future<DateTime?> _pickDateTime(DateTime? initial) async {
    final now = DateTime.now();
    final initDate = initial ?? now;

    final date = await showDatePicker(
      context: context,
      initialDate: initDate,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now.add(const Duration(days: 365 * 5)),
    );
    if (date == null || !mounted) return null;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initDate),
    );
    if (time == null) return null;

    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  String _fmtDateTime(DateTime dt) {
    final d =
        '${dt.day.toString().padLeft(2, '0')}/'
        '${dt.month.toString().padLeft(2, '0')}/'
        '${dt.year}';
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$d  $h:$m';
  }

  // ── Sección alarma/notificación ───────────────────────────────────────────

  Widget _buildAlarmSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 24),
        const Text(
          'Recordatorios',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),

        // ── Con alarma ───────────────────────────────────────────────────────
        _CheckRow(
          icon: Icons.alarm,
          label: 'Con alarma',
          value: _hasAlarm,
          color: Colors.red.shade700,
          onChanged: (v) {
            setState(() {
              _hasAlarm = v;
              if (!v) _alarmDateTime = null;
            });
          },
        ),
        if (_hasAlarm)
          _DateTimePickerRow(
            label: _alarmDateTime != null
                ? _fmtDateTime(_alarmDateTime!)
                : 'Seleccionar fecha y hora',
            onTap: () async {
              final dt = await _pickDateTime(_alarmDateTime);
              if (dt != null) setState(() => _alarmDateTime = dt);
            },
          ),

        const SizedBox(height: 4),

        // ── Con notificación ─────────────────────────────────────────────────
        _CheckRow(
          icon: Icons.notifications_outlined,
          label: 'Con notificación',
          value: _hasNotification,
          color: Colors.blue.shade700,
          onChanged: (v) {
            setState(() {
              _hasNotification = v;
              if (!v) _notifDateTime = null;
            });
          },
        ),
        if (_hasNotification)
          _DateTimePickerRow(
            label: _notifDateTime != null
                ? _fmtDateTime(_notifDateTime!)
                : 'Seleccionar fecha y hora',
            onTap: () async {
              final dt = await _pickDateTime(_notifDateTime);
              if (dt != null) setState(() => _notifDateTime = dt);
            },
          ),

        const SizedBox(height: 4),

        // ── Solo para mí ─────────────────────────────────────────────────────
        _CheckRow(
          icon: Icons.lock_outline,
          label: 'Solo para mí',
          value: _soloParaMi,
          color: Colors.grey.shade700,
          onChanged: (v) => setState(() => _soloParaMi = v),
        ),
      ],
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isChecklist = _tipo == Tipo.Checklist;

    return AlertDialog(
      title: Text(_isEditing ? 'Editar evento' : 'Añadir evento'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Título
              TextField(
                controller: _titleController,
                decoration: const InputDecoration(labelText: 'Título'),
              ),
              const SizedBox(height: 8),

              // Categoría
              DropdownButtonFormField<String>(
                value: _category,
                items: const [
                  DropdownMenuItem(value: 'Trabajo', child: Text('Trabajo')),
                  DropdownMenuItem(value: 'Eventos', child: Text('Eventos')),
                  DropdownMenuItem(value: 'Citas', child: Text('Citas')),
                  DropdownMenuItem(
                    value: 'Recordatorios',
                    child: Text('Recordatorios'),
                  ),
                  DropdownMenuItem(value: 'Bebé', child: Text('Bebé')),
                  DropdownMenuItem(value: 'Período', child: Text('Período')),
                ],
                onChanged: (v) {
                  if (v != null) {
                    setState(() {
                      _category = v;
                      final tipos = _tiposPorCategoria[v] ?? Tipo.values;
                      _tipo = tipos.first;
                    });
                  }
                },
                decoration: const InputDecoration(labelText: 'Categoría'),
              ),
              const SizedBox(height: 8),

              // Tipo
              DropdownButtonFormField<Tipo>(
                value: _tipo,
                items: _tiposActuales
                    .map(
                      (t) => DropdownMenuItem(
                        value: t,
                        child: Row(
                          children: [
                            if (t == Tipo.Checklist)
                              const Padding(
                                padding: EdgeInsets.only(right: 6),
                                child: Icon(Icons.checklist, size: 18),
                              ),
                            Text(_tipoLabel(t)),
                          ],
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _tipo = v);
                },
                decoration: const InputDecoration(labelText: 'Tipo'),
              ),
              const SizedBox(height: 8),

              // Horas
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: _pickStart,
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Hora inicio',
                        ),
                        child: Text(_start.format(context)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: InkWell(
                      onTap: _pickEnd,
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Hora fin',
                        ),
                        child: Text(_end.format(context)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Descripción
              TextField(
                controller: _descController,
                decoration: const InputDecoration(labelText: 'Descripción'),
                maxLines: 2,
              ),

              // Checklist
              if (isChecklist) ...[
                const SizedBox(height: 16),
                const Divider(),
                Row(
                  children: const [
                    Icon(Icons.checklist, size: 18),
                    SizedBox(width: 6),
                    Text(
                      'Items del checklist',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _itemController,
                        decoration: const InputDecoration(
                          labelText: 'Nuevo item',
                          isDense: true,
                        ),
                        onSubmitted: (_) => _addChecklistItem(),
                        textInputAction: TextInputAction.done,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      onPressed: _addChecklistItem,
                    ),
                  ],
                ),
                if (_checklistItems.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Column(
                      children: _checklistItems.asMap().entries.map((e) {
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(
                            Icons.check_box_outline_blank,
                            size: 20,
                            color: Colors.grey,
                          ),
                          title: Text(
                            e.value,
                            style: const TextStyle(fontSize: 14),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.close, size: 16),
                            onPressed: () =>
                                setState(() => _checklistItems.removeAt(e.key)),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
              ],

              // Alarma / Notificación / Solo para mí
              _buildAlarmSection(),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: () {
            final title = _titleController.text.trim();
            if (title.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Introduce un título')),
              );
              return;
            }
            final sMin = _start.hour * 60 + _start.minute;
            final eMin = _end.hour * 60 + _end.minute;
            if (eMin <= sMin) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'La hora de fin debe ser posterior a la de inicio',
                  ),
                ),
              );
              return;
            }
            if (_hasAlarm && _alarmDateTime == null) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Selecciona la fecha y hora de la alarma'),
                ),
              );
              return;
            }
            if (_hasNotification && _notifDateTime == null) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Selecciona la fecha y hora de la notificación',
                  ),
                ),
              );
              return;
            }
            Navigator.of(context).pop({
              'title': title,
              'category': _category,
              'tipo': _tipo,
              'start': _start,
              'end': _end,
              'description': _descController.text.trim(),
              'checklistItems': List<String>.from(_checklistItems),
              'hasAlarm': _hasAlarm,
              'alarmAt': _alarmDateTime,
              'hasNotif': _hasNotification,
              'notifAt': _notifDateTime,
              'soloParaMi': _soloParaMi,
            });
          },
          child: Text(_isEditing ? 'Guardar' : 'Añadir'),
        ),
      ],
    );
  }
}

// ── Widgets auxiliares del diálogo ─────────────────────────────────────────────

/// Fila con checkbox + icono + etiqueta
class _CheckRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool value;
  final Color color;
  final void Function(bool) onChanged;

  const _CheckRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.onChanged,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
        child: Row(
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Icon(
                value ? Icons.check_box : Icons.check_box_outline_blank,
                key: ValueKey(value),
                color: value ? color : Colors.grey.shade400,
                size: 22,
              ),
            ),
            const SizedBox(width: 8),
            Icon(icon, size: 18, color: value ? color : Colors.grey.shade400),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: value ? Colors.black87 : Colors.grey.shade500,
                fontWeight: value ? FontWeight.w500 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Fila que muestra la fecha/hora seleccionada y permite cambiarla
class _DateTimePickerRow extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _DateTimePickerRow({required this.label, required this.onTap, Key? key})
    : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 32, bottom: 4, top: 2),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Row(
            children: [
              const Icon(Icons.calendar_today, size: 16, color: Colors.black54),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(fontSize: 13, color: Colors.black87),
              ),
              const Spacer(),
              const Icon(Icons.chevron_right, size: 18, color: Colors.black38),
            ],
          ),
        ),
      ),
    );
  }
}
