// lib/views/shifts_screen.dart

import 'package:flutter/material.dart';
import '../models/shift_model.dart';
import '../core/shift_repository.dart';

// ── Paleta de 10 colores predefinidos ─────────────────────────────────────────
const List<_ColorOption> _kColors = [
  _ColorOption(color: Color(0xFFFF9800), label: 'Naranja'),
  _ColorOption(color: Color(0xFFF44336), label: 'Rojo'),
  _ColorOption(color: Color(0xFFE91E63), label: 'Rosa'),
  _ColorOption(color: Color(0xFF9C27B0), label: 'Morado'),
  _ColorOption(color: Color(0xFF3F51B5), label: 'Índigo'),
  _ColorOption(color: Color(0xFF2196F3), label: 'Azul'),
  _ColorOption(color: Color(0xFF009688), label: 'Verde azulado'),
  _ColorOption(color: Color(0xFF4CAF50), label: 'Verde'),
  _ColorOption(color: Color(0xFF795548), label: 'Marrón'),
  _ColorOption(color: Color(0xFF607D8B), label: 'Gris azulado'),
];

class _ColorOption {
  final Color color;
  final String label;
  const _ColorOption({required this.color, required this.label});
}

// ── Pantalla principal de Turnos ──────────────────────────────────────────────

class ShiftsScreen extends StatefulWidget {
  const ShiftsScreen({Key? key}) : super(key: key);

  @override
  State<ShiftsScreen> createState() => _ShiftsScreenState();
}

class _ShiftsScreenState extends State<ShiftsScreen> {
  List<ShiftModel> _shifts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await ShiftRepository.instance.seedDefaults();
    await _reload();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    try {
      final shifts = await ShiftRepository.instance.getAll();
      if (mounted) setState(() => _shifts = shifts);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Abrir diálogo crear / editar ──────────────────────────────────────────

  Future<void> _openDialog({ShiftModel? shift}) async {
    final result = await showDialog<ShiftModel?>(
      context: context,
      builder: (_) => _ShiftDialog(initial: shift),
    );
    if (result == null) return;

    try {
      await ShiftRepository.instance.save(result);
      await _reload();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error al guardar: $e')));
      }
    }
  }

  // ── Borrar ────────────────────────────────────────────────────────────────

  Future<void> _delete(ShiftModel shift) async {
    if (shift.id == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Borrar turno'),
        content: Text('¿Borrar el turno "${shift.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Borrar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ShiftRepository.instance.delete(shift.id!);
    await _reload();
  }

  // ── Helpers de formato ────────────────────────────────────────────────────

  String _fmtTime(TimeOfDay t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String _fmtDuration(ShiftModel s) {
    final h = s.durationHours;
    final hInt = h.truncate();
    final mInt = ((h - hInt) * 60).round();
    return mInt == 0 ? '${hInt}h' : '${hInt}h ${mInt}min';
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Turnos'), elevation: 1),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openDialog(),
        icon: const Icon(Icons.add),
        label: const Text('Crear turno'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _shifts.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.work_outline,
                    size: 64,
                    color: Colors.grey.shade300,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Sin turnos todavía',
                    style: TextStyle(color: Colors.grey.shade500),
                  ),
                ],
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              itemCount: _shifts.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) => _ShiftCard(
                shift: _shifts[i],
                fmtTime: _fmtTime,
                fmtDuration: _fmtDuration,
                onEdit: () => _openDialog(shift: _shifts[i]),
                onDelete: () => _delete(_shifts[i]),
              ),
            ),
    );
  }
}

// ── Tarjeta de turno ──────────────────────────────────────────────────────────

class _ShiftCard extends StatelessWidget {
  final ShiftModel shift;
  final String Function(TimeOfDay) fmtTime;
  final String Function(ShiftModel) fmtDuration;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ShiftCard({
    required this.shift,
    required this.fmtTime,
    required this.fmtDuration,
    required this.onEdit,
    required this.onDelete,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final c = shift.color;
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: c.withOpacity(0.4), width: 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              // ── Indicador de color ──────────────────────────────────────
              Container(
                width: 6,
                height: 64,
                decoration: BoxDecoration(
                  color: c,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 14),
              // ── Datos ───────────────────────────────────────────────────
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      shift.name,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: c,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(
                          Icons.access_time,
                          size: 14,
                          color: Colors.black54,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${fmtTime(shift.from)} — ${fmtTime(shift.to)}  (${fmtDuration(shift)})',
                          style: const TextStyle(
                            fontSize: 13,
                            color: Colors.black54,
                          ),
                        ),
                      ],
                    ),
                    if (shift.euroPerHour != null) ...[
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          const Icon(
                            Icons.euro,
                            size: 13,
                            color: Colors.black45,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            '${shift.euroPerHour!.toStringAsFixed(2)} €/h'
                            '  →  ${shift.earningsPerShift!.toStringAsFixed(2)} € / turno',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.black45,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              // ── Acciones ────────────────────────────────────────────────
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    tooltip: 'Editar',
                    onPressed: onEdit,
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.delete_outline,
                      color: Colors.redAccent,
                    ),
                    tooltip: 'Borrar',
                    onPressed: onDelete,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Diálogo crear / editar turno ──────────────────────────────────────────────

class _ShiftDialog extends StatefulWidget {
  final ShiftModel? initial;
  const _ShiftDialog({this.initial, Key? key}) : super(key: key);

  @override
  State<_ShiftDialog> createState() => _ShiftDialogState();
}

class _ShiftDialogState extends State<_ShiftDialog> {
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _euroCtrl = TextEditingController();

  late Color _color;
  late TimeOfDay _from;
  late TimeOfDay _to;

  bool get _isEditing => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final s = widget.initial;
    if (s != null) {
      _nameCtrl.text = s.name;
      _color = s.color;
      _from = s.from;
      _to = s.to;
      if (s.euroPerHour != null) {
        _euroCtrl.text = s.euroPerHour!.toStringAsFixed(2);
      }
    } else {
      _color = _kColors.first.color;
      _from = const TimeOfDay(hour: 8, minute: 0);
      _to = const TimeOfDay(hour: 16, minute: 0);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _euroCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickTime({required bool isFrom}) async {
    final initial = isFrom ? _from : _to;
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked == null) return;
    setState(() {
      if (isFrom)
        _from = picked;
      else
        _to = picked;
    });
  }

  String _fmtTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEditing ? 'Editar turno' : 'Nuevo turno'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Nombre ──────────────────────────────────────────────────────
            TextField(
              controller: _nameCtrl,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Nombre del turno',
                hintText: 'Ej. MAÑANA',
              ),
            ),
            const SizedBox(height: 16),

            // ── Color ────────────────────────────────────────────────────────
            const Text(
              'Color',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: _kColors.map((opt) {
                final selected = opt.color.value == _color.value;
                return GestureDetector(
                  onTap: () => setState(() => _color = opt.color),
                  child: Tooltip(
                    message: opt.label,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: opt.color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: selected ? Colors.black87 : Colors.transparent,
                          width: 2.5,
                        ),
                        boxShadow: selected
                            ? [
                                BoxShadow(
                                  color: opt.color.withOpacity(0.4),
                                  blurRadius: 6,
                                  spreadRadius: 1,
                                ),
                              ]
                            : [],
                      ),
                      child: selected
                          ? const Icon(
                              Icons.check,
                              color: Colors.white,
                              size: 18,
                            )
                          : null,
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),

            // ── Horas ────────────────────────────────────────────────────────
            const Text(
              'Horario',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => _pickTime(isFrom: true),
                    borderRadius: BorderRadius.circular(8),
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Desde',
                        isDense: true,
                      ),
                      child: Text(_fmtTime(_from)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InkWell(
                    onTap: () => _pickTime(isFrom: false),
                    borderRadius: BorderRadius.circular(8),
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Hasta',
                        isDense: true,
                      ),
                      child: Text(_fmtTime(_to)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ── Euro/hora (opcional) ─────────────────────────────────────────
            const Text(
              'Retribución (opcional)',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _euroCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: '€ / hora',
                hintText: 'Ej. 10.50',
                prefixIcon: Icon(Icons.euro, size: 18),
                isDense: true,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: () {
            final name = _nameCtrl.text.trim();
            if (name.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Introduce un nombre')),
              );
              return;
            }
            final euroText = _euroCtrl.text.trim();
            final euro = euroText.isEmpty
                ? null
                : double.tryParse(euroText.replaceAll(',', '.'));
            if (euroText.isNotEmpty && euro == null) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Valor €/hora no válido')),
              );
              return;
            }

            final result = ShiftModel(
              id: widget.initial?.id,
              name: name,
              color: _color,
              from: _from,
              to: _to,
              euroPerHour: euro,
              sortOrder: widget.initial?.sortOrder ?? 99,
            );
            Navigator.of(context).pop(result);
          },
          child: Text(_isEditing ? 'Guardar' : 'Crear'),
        ),
      ],
    );
  }
}
