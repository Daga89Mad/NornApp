// lib/views/share_with_picker.dart
//
// Selector "Compartir con" para los diálogos de crear de las vistas semanales
// (tareas, menús, entrenamientos).
//
// · Carga los amigos con cuenta (firebaseUid).
// · Preselecciona a quienes ya tienen el reparto global de ese tipo
//   (weekly_shares), así por defecto se comparte como siempre.
// · El usuario puede quitar o añadir personas solo para este item.
// · Si no hay amigos, no muestra nada.

import 'package:flutter/material.dart';
import '../core/friend_repository.dart';
import '../core/weekly_share_service.dart';
import '../models/friend_model.dart';

class ShareWithPicker extends StatefulWidget {
  /// 'tasks' | 'menus' | 'trainings'
  final String type;
  final Color accent;
  final ValueChanged<Set<String>> onChanged;

  /// Opcional: de dónde sale la preselección. Si es null se usa el reparto
  /// global de [type] (weekly_shares). El calendario lo usa para preseleccionar
  /// el reparto del evento o el de su categoría.
  final Future<Set<String>> Function()? loadInitial;

  /// Si es false, [onChanged] solo se llama cuando el usuario toca un chip
  /// (no al cargar la preselección).
  final bool notifyInitial;

  const ShareWithPicker({
    Key? key,
    required this.type,
    required this.accent,
    required this.onChanged,
    this.loadInitial,
    this.notifyInitial = true,
  }) : super(key: key);

  @override
  State<ShareWithPicker> createState() => _ShareWithPickerState();
}

class _ShareWithPickerState extends State<ShareWithPicker> {
  List<FriendModel> _friends = [];
  final Set<String> _selected = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    List<FriendModel> friends = [];
    Set<String> global = {};
    try {
      friends = (await FriendRepository.instance.getAll())
          .where((f) => (f.firebaseUid ?? '').isNotEmpty)
          .toList();
    } catch (_) {}
    try {
      global = widget.loadInitial != null
          ? await widget.loadInitial!()
          : (await WeeklyShareService.instance.getSharedUidsForType(
              widget.type,
            )).toSet();
    } catch (_) {}
    if (!mounted) return;
    final validUids = friends.map((f) => f.firebaseUid!).toSet();
    setState(() {
      _friends = friends;
      _selected
        ..clear()
        ..addAll(global.where(validUids.contains));
      _loading = false;
    });
    if (widget.notifyInitial) widget.onChanged(Set<String>.from(_selected));
  }

  void _toggle(String uid) {
    setState(() {
      if (!_selected.remove(uid)) _selected.add(uid);
    });
    widget.onChanged(Set<String>.from(_selected));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: LinearProgressIndicator(minHeight: 2),
      );
    }
    if (_friends.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        const Text(
          'Compartir con',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _friends.map((f) {
            final uid = f.firebaseUid!;
            final sel = _selected.contains(uid);
            return FilterChip(
              avatar: Text(f.logo, style: const TextStyle(fontSize: 16)),
              label: Text(f.displayName),
              selected: sel,
              showCheckmark: false,
              selectedColor: widget.accent.withOpacity(0.25),
              side: BorderSide(
                color: sel ? widget.accent : Colors.grey.shade400,
              ),
              onSelected: (_) => _toggle(uid),
            );
          }).toList(),
        ),
        const SizedBox(height: 4),
        Text(
          _selected.isEmpty ? 'Solo para ti' : 'Lo verán las personas marcadas',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
      ],
    );
  }
}
