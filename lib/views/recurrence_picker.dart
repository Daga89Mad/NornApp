// lib/views/recurrence_picker.dart
//
// Selector de repetición reutilizable (tareas, menús, entrenamiento y
// calendario). Se coloca dentro de cualquier diálogo y avisa con [onChanged]
// cada vez que cambia la regla.
//
//   RecurrencePicker(
//     startDate: selectedDay,
//     accent: _accent,
//     onChanged: (r) => rule = r,
//   )

import 'package:flutter/material.dart';
import '../core/recurrence_rule.dart';
import '../core/week_dates.dart';

class RecurrencePicker extends StatefulWidget {
  /// Fecha "desde" (la del propio elemento).
  final DateTime startDate;
  final RecurrenceRule initial;
  final Color accent;
  final ValueChanged<RecurrenceRule> onChanged;

  const RecurrencePicker({
    Key? key,
    required this.startDate,
    required this.onChanged,
    this.initial = RecurrenceRule.none,
    this.accent = Colors.teal,
  }) : super(key: key);

  @override
  State<RecurrencePicker> createState() => _RecurrencePickerState();
}

class _RecurrencePickerState extends State<RecurrencePicker> {
  late RecurrenceRule _rule;

  /// true cuando el usuario eligió a mano la fecha "hasta"; si no, la fecha
  /// final se recalcula al cambiar la frecuencia o el día de inicio.
  bool _untilTouched = false;

  static const _options = <(RecurrenceFreq, String)>[
    (RecurrenceFreq.none, 'No repetir'),
    (RecurrenceFreq.daily, 'Cada día'),
    (RecurrenceFreq.weekly, 'Cada semana'),
    (RecurrenceFreq.biweekly, 'Cada 2 semanas'),
    (RecurrenceFreq.monthly, 'Cada mes'),
    (RecurrenceFreq.everyNDays, 'Cada X días'),
  ];

  @override
  void initState() {
    super.initState();
    _rule = widget.initial;
    _untilTouched = widget.initial.until != null;
    if (!_rule.isNone && _rule.until == null) {
      _rule = _rule.copyWith(until: _rule.defaultUntil(widget.startDate));
    }
  }

  @override
  void didUpdateWidget(covariant RecurrencePicker old) {
    super.didUpdateWidget(old);
    if (isSameDay(old.startDate, widget.startDate) || _rule.isNone) return;

    final until = _rule.until;
    if (!_untilTouched || until == null || until.isBefore(widget.startDate)) {
      _rule = _rule.copyWith(until: _rule.defaultUntil(widget.startDate));
      _untilTouched = false;
      // Se notifica después del build para no llamar a setState del padre
      // mientras se está construyendo.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onChanged(_rule);
      });
    }
  }

  void _emit(RecurrenceRule r) {
    setState(() => _rule = r);
    widget.onChanged(r);
  }

  void _selectFreq(RecurrenceFreq f) {
    var r = _rule.copyWith(freq: f);
    if (f == RecurrenceFreq.none) {
      r = r.copyWith(clearUntil: true);
      _untilTouched = false;
    } else if (!_untilTouched) {
      r = r.copyWith(until: r.defaultUntil(widget.startDate));
    }
    _emit(r);
  }

  void _changeInterval(int delta) {
    final n = (_rule.interval + delta).clamp(1, 365);
    var r = _rule.copyWith(interval: n);
    if (!_untilTouched) r = r.copyWith(until: r.defaultUntil(widget.startDate));
    _emit(r);
  }

  Future<void> _pickUntil() async {
    final start = startOfDay(widget.startDate);
    final current = _rule.until ?? _rule.defaultUntil(start);
    final picked = await showDatePicker(
      context: context,
      initialDate: current.isBefore(start) ? start : current,
      firstDate: start,
      lastDate: DateTime(start.year + 3, start.month, start.day),
      helpText: 'Repetir hasta',
    );
    if (picked == null) return;
    _untilTouched = true;
    _emit(_rule.copyWith(until: picked));
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent;
    final count = _rule.isNone ? 1 : _rule.occurrences(widget.startDate).length;
    final truncated = !_rule.isNone && _rule.isTruncated(widget.startDate);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Repetir', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 2,
          children: _options.map((opt) {
            return ChoiceChip(
              label: Text(opt.$2, style: const TextStyle(fontSize: 12)),
              selected: _rule.freq == opt.$1,
              selectedColor: accent.withOpacity(0.3),
              onSelected: (_) => _selectFreq(opt.$1),
            );
          }).toList(),
        ),

        // ── Cada X días ──────────────────────────────────────────────────────
        if (_rule.freq == RecurrenceFreq.everyNDays) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              const Text('Cada'),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.remove_circle_outline),
                onPressed: _rule.interval > 1
                    ? () => _changeInterval(-1)
                    : null,
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${_rule.interval}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.add_circle_outline),
                onPressed: () => _changeInterval(1),
              ),
              Text(_rule.interval == 1 ? 'día' : 'días'),
            ],
          ),
        ],

        // ── Desde / Hasta ────────────────────────────────────────────────────
        if (!_rule.isNone) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Desde',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  child: Text(
                    RecurrenceRule.fmtDate(widget.startDate),
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: InkWell(
                  onTap: _pickUntil,
                  borderRadius: BorderRadius.circular(4),
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Hasta',
                      border: OutlineInputBorder(),
                      isDense: true,
                      suffixIcon: Icon(Icons.event, size: 18),
                    ),
                    child: Text(
                      RecurrenceRule.fmtDate(
                        _rule.until ?? _rule.defaultUntil(widget.startDate),
                      ),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            truncated
                ? 'Se crearán $count repeticiones (máximo permitido).'
                : 'Se crearán $count repeticiones.',
            style: TextStyle(
              fontSize: 12,
              color: truncated ? Colors.orange.shade800 : Colors.grey.shade600,
            ),
          ),
        ],
      ],
    );
  }
}
