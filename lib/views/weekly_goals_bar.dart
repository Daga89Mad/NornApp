// lib/views/weekly_goals_bar.dart
//
// Franja de "Objetivos de la semana" que va en la parte superior de las
// pantallas semanales (Menús, Tareas y Entrenamiento).
//
// Un objetivo es algo para esa semana sin día fijo: "Perder 2 kilos",
// "Escuchar un podcast", "Correr 20 km"… Se pueden marcar como conseguidos,
// editar, borrar y compartir con amigos (ver WeeklyGoalRepository).

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../core/friend_repository.dart';
import '../core/weekly_goal_repository.dart';
import '../models/friend_model.dart';
import '../models/weekly_goal_model.dart';

class WeeklyGoalsBar extends StatefulWidget {
  /// 'menus' | 'tasks' | 'trainings'
  final String type;

  /// Cualquier día de la semana que se está viendo (normalmente el lunes).
  final DateTime weekStart;

  /// Color principal de la pantalla.
  final Color color;

  /// Ejemplo que se muestra al crear (p. ej. 'Perder 2 kilos').
  final String hint;

  const WeeklyGoalsBar({
    Key? key,
    required this.type,
    required this.weekStart,
    required this.color,
    this.hint = 'Escribe tu objetivo',
  }) : super(key: key);

  @override
  State<WeeklyGoalsBar> createState() => _WeeklyGoalsBarState();
}

class _WeeklyGoalsBarState extends State<WeeklyGoalsBar> {
  final _repo = WeeklyGoalRepository.instance;
  StreamSubscription<List<WeeklyGoal>>? _sub;
  List<WeeklyGoal> _goals = const [];
  bool _expanded = true;

  String get _myUid => FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(covariant WeeklyGoalsBar old) {
    super.didUpdateWidget(old);
    if (old.type != widget.type ||
        WeeklyGoal.weekKeyOf(old.weekStart) !=
            WeeklyGoal.weekKeyOf(widget.weekStart)) {
      _subscribe();
    }
  }

  void _subscribe() {
    _sub?.cancel();
    _goals = const []; // initState/didUpdateWidget ya provocan un build
    
    _sub = _repo.watchWeek(widget.type, widget.weekStart).listen((goals) {
      if (mounted) setState(() => _goals = goals);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  // ── Acciones ──────────────────────────────────────────────────────────────

  Future<String?> _askTitle({String initial = '', required String title}) {
    final ctrl = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            hintText: 'Ej.: ${widget.hint}',
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: widget.color),
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('Guardar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _create() async {
    final title = await _askTitle(title: 'Nuevo objetivo de la semana');
    if (title == null || title.trim().isEmpty) return;
    try {
      await _repo.create(
        type: widget.type,
        anyDayOfWeek: widget.weekStart,
        title: title,
      );
      if (mounted) setState(() => _expanded = true);
    } catch (e) {
      _showError('No se pudo crear el objetivo: $e');
    }
  }

  Future<void> _edit(WeeklyGoal g) async {
    final title = await _askTitle(initial: g.title, title: 'Editar objetivo');
    if (title == null || title.trim().isEmpty) return;
    try {
      await _repo.rename(g, title);
    } catch (e) {
      _showError('No se pudo guardar: $e');
    }
  }

  Future<void> _toggle(WeeklyGoal g) async {
    try {
      await _repo.toggleDone(g);
    } catch (e) {
      _showError('No se pudo actualizar: $e');
    }
  }

  Future<void> _delete(WeeklyGoal g) async {
    final foreign = g.isSharedFromOther(_myUid);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(foreign ? 'Quitar objetivo' : 'Eliminar objetivo'),
        content: Text(
          foreign
              ? '¿Quitar "${g.title}" de tu semana? Quien lo comparte lo seguirá teniendo.'
              : '¿Eliminar "${g.title}"? También desaparecerá para las personas con las que lo compartes.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              foreign ? 'Quitar' : 'Eliminar',
              style: const TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _repo.delete(g);
    } catch (e) {
      _showError('No se pudo borrar: $e');
    }
  }

  Future<void> _share(WeeklyGoal g) async {
    final friends = (await FriendRepository.instance.getAll())
        .where((f) => f.firebaseUid != null)
        .toList();
    if (!mounted) return;
    if (friends.isEmpty) {
      _showError('No tienes amigos para compartir');
      return;
    }
    final selected = await showDialog<Set<String>>(
      context: context,
      builder: (ctx) => _ShareGoalDialog(
        goal: g,
        friends: friends,
        color: widget.color,
      ),
    );
    if (selected == null) return;
    try {
      await _repo.setSharedWith(g, selected);
    } catch (e) {
      _showError('No se pudo compartir: $e');
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final done = _goals.where((g) => g.isDone).length;

    return Material(
      color: widget.color.withOpacity(0.07),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: _goals.isEmpty
                ? _create
                : () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
              child: Row(
                children: [
                  Icon(Icons.flag_outlined, size: 20, color: widget.color),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _goals.isEmpty
                          ? 'Objetivos de la semana'
                          : 'Objetivos de la semana  ($done/${_goals.length})',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: widget.color,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: widget.color,
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: _create,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Objetivo'),
                  ),
                  if (_goals.isNotEmpty)
                    Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                      color: widget.color,
                    ),
                ],
              ),
            ),
          ),
          if (_expanded && _goals.isNotEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 170),
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: 6),
                children: [for (final g in _goals) _goalTile(g)],
              ),
            ),
        ],
      ),
    );
  }

  Widget _goalTile(WeeklyGoal g) {
    final foreign = g.isSharedFromOther(_myUid);
    final sharedByMe = !foreign && g.sharedWith.isNotEmpty;

    return InkWell(
      onTap: () => _toggle(g),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 2, 4, 2),
        child: Row(
          children: [
            Icon(
              g.isDone ? Icons.check_circle : Icons.radio_button_unchecked,
              size: 22,
              color: g.isDone ? widget.color : Colors.grey,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    g.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      decoration: g.isDone ? TextDecoration.lineThrough : null,
                      color: g.isDone ? Colors.grey : null,
                    ),
                  ),
                  if (foreign)
                    Text(
                      'Compartido por ${g.ownerName.isNotEmpty ? g.ownerName : "otra persona"}',
                      style: const TextStyle(fontSize: 11, color: Colors.teal),
                    ),
                ],
              ),
            ),
            if (foreign || sharedByMe)
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Icon(
                  Icons.people_alt_outlined,
                  size: 16,
                  color: foreign ? Colors.teal : Colors.grey.shade500,
                ),
              ),
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, size: 20, color: Colors.grey.shade600),
              onSelected: (v) {
                switch (v) {
                  case 'edit':
                    _edit(g);
                    break;
                  case 'share':
                    _share(g);
                    break;
                  case 'delete':
                    _delete(g);
                    break;
                }
              },
              itemBuilder: (_) => [
                if (!foreign)
                  const PopupMenuItem(value: 'edit', child: Text('Editar')),
                if (!foreign)
                  const PopupMenuItem(value: 'share', child: Text('Compartir')),
                PopupMenuItem(
                  value: 'delete',
                  child: Text(
                    foreign ? 'Quitar de mi semana' : 'Eliminar',
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Selector de amigos para compartir un objetivo. Devuelve el conjunto de
/// UIDs con los que debe quedar compartido, o null si se cancela.
class _ShareGoalDialog extends StatefulWidget {
  final WeeklyGoal goal;
  final List<FriendModel> friends;
  final Color color;

  const _ShareGoalDialog({
    required this.goal,
    required this.friends,
    required this.color,
  });

  @override
  State<_ShareGoalDialog> createState() => _ShareGoalDialogState();
}

class _ShareGoalDialogState extends State<_ShareGoalDialog> {
  late final Set<String> _selected = {...widget.goal.sharedWith};

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Compartir objetivo'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final f in widget.friends)
              CheckboxListTile(
                value: _selected.contains(f.firebaseUid),
                activeColor: widget.color,
                secondary: Text(f.logo, style: const TextStyle(fontSize: 22)),
                title: Text(f.displayName),
                onChanged: (v) => setState(() {
                  if (v == true) {
                    _selected.add(f.firebaseUid!);
                  } else {
                    _selected.remove(f.firebaseUid);
                  }
                }),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: widget.color),
          onPressed: () => Navigator.pop(context, _selected),
          child: const Text('Guardar', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}
