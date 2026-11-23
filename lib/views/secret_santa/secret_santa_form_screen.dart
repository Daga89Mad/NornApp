// lib/views/secret_santa/secret_santa_form_screen.dart
//
// Crear o editar un AMIGO INVISIBLE: nombre, límite de gasto, fecha de
// entrega, notas e invitados (de la lista de Amigos). Devuelve el id.

import 'package:flutter/material.dart';
import '../../core/secret_santa_repository.dart';
import '../../models/secret_santa_models.dart';
import 'secret_santa_widgets.dart';

class SecretSantaFormScreen extends StatefulWidget {
  final SecretSantaGame? game; // null → crear
  const SecretSantaFormScreen({super.key, this.game});

  @override
  State<SecretSantaFormScreen> createState() => _SecretSantaFormScreenState();
}

class _SecretSantaFormScreenState extends State<SecretSantaFormScreen> {
  final _repo = SecretSantaRepository.instance;
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _budget;
  late final TextEditingController _notes;
  DateTime? _date;
  bool _joinMyself = true;
  bool _saving = false;

  SantaPeople? _people;

  /// uid → nombre de los invitados marcados (sin mí).
  final Map<String, String> _selected = {};

  /// Invitados que ya estaban en el juego pero no son amigos míos.
  final Map<String, String> _extra = {};

  bool get _editing => widget.game != null;

  @override
  void initState() {
    super.initState();
    final g = widget.game;
    _name = TextEditingController(text: g?.name ?? 'Amigo invisible');
    _budget = TextEditingController(
      text: g == null || g.budgetCents == 0
          ? ''
          : (g.budgetCents % 100 == 0
                ? '${g.budgetCents ~/ 100}'
                : (g.budgetCents / 100).toStringAsFixed(2).replaceAll('.', ',')),
    );
    _notes = TextEditingController(text: g?.notes ?? '');
    _date = g?.eventDate;
    if (g != null) {
      for (final uid in g.invited) {
        if (uid == _repo.uid) continue;
        _selected[uid] = g.names[uid] ?? '';
      }
    }
    SantaPeople.load(_repo.uid).then((p) {
      if (!mounted) return;
      setState(() {
        _people = p;
        for (final e in _selected.entries) {
          if (!p.friendsByUid.containsKey(e.key)) _extra[e.key] = e.value;
        }
      });
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _budget.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _date ?? DateTime(now.year, 12, 24),
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3),
      helpText: 'Día de la entrega de regalos',
    );
    if (d != null) setState(() => _date = d);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invita al menos a un amigo')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final cents = parseBudget(_budget.text) ?? 0;
      final names = Map<String, String>.from(_selected);
      String id;
      if (_editing) {
        id = widget.game!.id;
        await _repo.updateGame(
          id,
          name: _name.text,
          budgetCents: cents,
          eventDate: _date,
          notes: _notes.text,
          invitedNames: names,
          currentParticipants: widget.game!.participants,
        );
      } else {
        id = await _repo.createGame(
          name: _name.text,
          budgetCents: cents,
          eventDate: _date,
          notes: _notes.text,
          invitedNames: names,
          joinMyself: _joinMyself,
        );
      }
      if (mounted) Navigator.of(context).pop(id);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo guardar: $e')));
    }
  }

  InputDecoration _deco(String label, IconData icon, {String? hint}) =>
      InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final people = _people;
    return Scaffold(
      backgroundColor: SantaColors.background,
      appBar: AppBar(
        backgroundColor: SantaColors.primary,
        foregroundColor: Colors.white,
        title: Text(_editing ? 'Editar sorteo' : 'Nuevo amigo invisible'),
        flexibleSpace: Container(
          decoration: const BoxDecoration(gradient: SantaColors.header),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: SantaColors.primary,
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
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
            label: Text(_editing ? 'Guardar cambios' : 'Crear sorteo'),
          ),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              decoration: _deco('Nombre', Icons.card_giftcard_rounded),
              validator: (v) =>
                  (v ?? '').trim().isEmpty ? 'Pon un nombre' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _budget,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: _deco(
                'Límite de gasto (€)',
                Icons.euro_rounded,
                hint: 'Ej. 20 (vacío = sin límite)',
              ),
              validator: (v) =>
                  parseBudget(v ?? '') == null ? 'Importe no válido' : null,
            ),
            const SizedBox(height: 12),
            Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              child: ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                leading: const Icon(Icons.event_outlined),
                title: Text(
                  _date == null
                      ? 'Fecha de entrega (opcional)'
                      : 'Entrega: ${fmtSantaDate(_date!)}',
                ),
                trailing: _date == null
                    ? const Icon(Icons.chevron_right)
                    : IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() => _date = null),
                      ),
                onTap: _pickDate,
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _notes,
              maxLines: 3,
              minLines: 1,
              textCapitalization: TextCapitalization.sentences,
              decoration: _deco(
                'Notas (opcional)',
                Icons.notes_outlined,
                hint: 'Lugar de la cena, temática…',
              ),
            ),
            if (!_editing) ...[
              const SizedBox(height: 12),
              Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                child: SwitchListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  activeColor: SantaColors.primary,
                  secondary: const Icon(Icons.person_outline),
                  title: const Text('Yo también juego'),
                  subtitle: const Text('Apuntarme al sorteo'),
                  value: _joinMyself,
                  onChanged: (v) => setState(() => _joinMyself = v),
                ),
              ),
            ],
            const SizedBox(height: 22),
            Row(
              children: [
                const Text(
                  'Invitados',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                Text(
                  '${_selected.length} seleccionados',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Cada invitado decide si se apunta. Hacen falta al menos '
              '${SecretSantaGame.minPlayers} jugadores para sortear.',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
            const SizedBox(height: 10),
            if (people == null)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (people.friends.isEmpty && _extra.isEmpty)
              const SantaEmptyState(
                icon: Icons.group_add_outlined,
                title: 'No tienes amigos añadidos',
                subtitle: 'Añádelos desde Amigos en el menú principal.',
              )
            else
              SantaCard(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  children: [
                    for (final f in people.friends)
                      _inviteTile(f.firebaseUid!, f.displayName, people),
                    for (final e in _extra.entries)
                      _inviteTile(
                        e.key,
                        e.value.isEmpty ? 'Alguien' : e.value,
                        people,
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _inviteTile(String uid, String name, SantaPeople people) {
    final selected = _selected.containsKey(uid);
    final realName = people.friendsByUid[uid]?.name ?? name;
    return CheckboxListTile(
      value: selected,
      activeColor: SantaColors.primary,
      controlAffinity: ListTileControlAffinity.trailing,
      secondary: SantaAvatar(uid: uid, people: people, size: 36),
      title: Text(name),
      onChanged: (v) => setState(() {
        if (v == true) {
          _selected[uid] = realName;
        } else {
          _selected.remove(uid);
        }
      }),
    );
  }
}
