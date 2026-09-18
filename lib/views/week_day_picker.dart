// lib/views/week_day_picker.dart
//
// Selector de día reutilizable para los diálogos de crear tarea / menú /
// entrenamiento.
//
// Muestra los 7 días de la semana del día elegido y un chip "Otra fecha…" que
// abre el calendario completo, para poder crear items en cualquier semana sin
// tener que navegar con las flechas. Toda la aritmética usa week_dates, así que
// no se descuadra con el cambio de hora.

import 'package:flutter/material.dart';
import '../core/week_dates.dart';

const _wdDias = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
const _wdMeses = [
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

String _wdFmtLargo(DateTime d) =>
    '${_wdDias[d.weekday - 1]} ${d.day} ${_wdMeses[d.month]} ${d.year}';

class WeekDayPicker extends StatelessWidget {
  /// Lunes de la semana que se está viendo en la pantalla.
  final DateTime weekStart;

  /// Día actualmente elegido.
  final DateTime selectedDay;

  final Color accent;

  /// Se llama siempre con una fecha a medianoche.
  final ValueChanged<DateTime> onChanged;

  final DateTime? firstDate;
  final DateTime? lastDate;

  const WeekDayPicker({
    super.key,
    required this.weekStart,
    required this.selectedDay,
    required this.accent,
    required this.onChanged,
    this.firstDate,
    this.lastDate,
  });

  @override
  Widget build(BuildContext context) {
    // Se pintan los 7 días de la semana del día ELEGIDO, no de la visible: así,
    // al usar "Otra fecha…", los chips saltan a esa semana.
    final base = mondayOf(selectedDay);
    final bool otraSemana = base != mondayOf(weekStart);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            ...List.generate(7, (i) {
              final day = addDays(base, i);
              return ChoiceChip(
                label: Text(
                  '${_wdDias[day.weekday - 1]} ${day.day}',
                  style: const TextStyle(fontSize: 12),
                ),
                selected: isSameDay(day, selectedDay),
                selectedColor: accent.withOpacity(0.3),
                onSelected: (_) => onChanged(day),
              );
            }),
            ActionChip(
              avatar: Icon(Icons.event, size: 16, color: accent),
              label: const Text('Otra fecha…', style: TextStyle(fontSize: 12)),
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: selectedDay,
                  firstDate: firstDate ?? DateTime(2020),
                  lastDate: lastDate ?? DateTime(2100),
                  helpText: 'Elige el día',
                );
                if (picked != null) onChanged(startOfDay(picked));
              },
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          otraSemana
              ? 'Se guardará el ${_wdFmtLargo(selectedDay)} (otra semana)'
              : _wdFmtLargo(selectedDay),
          style: TextStyle(
            fontSize: 11,
            color: otraSemana ? accent : Colors.grey,
            fontWeight: otraSemana ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ],
    );
  }
}
