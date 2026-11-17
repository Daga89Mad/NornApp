// lib/views/event_change_prompt.dart
//
// Diálogo para que el DUEÑO de un evento acepte o rechace los cambios que
// propone otra persona con la que lo tiene compartido.

import 'package:flutter/material.dart';
import '../core/event_change_service.dart';

bool _eventPromptOpen = false;

/// Muestra una a una las propuestas pendientes sobre mis eventos.
/// Devuelve true si se ha aceptado alguna (para recargar la pantalla).
Future<bool> showPendingEventChanges(BuildContext context) async {
  if (_eventPromptOpen) return false;
  final pending = await EventChangeService.instance.pendingForMe();
  if (pending.isEmpty || !context.mounted) return false;

  _eventPromptOpen = true;
  bool acceptedAny = false;
  try {
    for (final p in pending) {
      if (!context.mounted) break;
      final bool? accepted = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _EventChangeDialog(proposal: p),
      );
      if (accepted == null) break; // "Más tarde"
      if (accepted) {
        final ok = await EventChangeService.instance.accept(p);
        acceptedAny = acceptedAny || ok;
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                ok
                    ? 'Cambios aplicados a «${p.eventTitle}»'
                    : 'No se pudo aplicar el cambio',
              ),
            ),
          );
        }
      } else {
        await EventChangeService.instance.reject(p);
      }
    }
  } finally {
    _eventPromptOpen = false;
  }
  return acceptedAny;
}

class _EventChangeDialog extends StatelessWidget {
  final EventChangeProposal proposal;
  const _EventChangeDialog({required this.proposal});

  static String _hm(Object? minutes) {
    final m = (minutes as num?)?.toInt() ?? 0;
    return '${(m ~/ 60).toString().padLeft(2, '0')}:'
        '${(m % 60).toString().padLeft(2, '0')}';
  }

  static String _day(DateTime d) {
    const days = ['lun', 'mar', 'mié', 'jue', 'vie', 'sáb', 'dom'];
    return '${days[d.weekday - 1]} ${d.day.toString().padLeft(2, '0')}/'
        '${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  List<Widget> _rows() {
    final p = proposal;
    final c = p.changes;
    final rows = <Widget>[];

    void add(IconData icon, String label, String value) => rows.add(
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: Colors.grey.shade700),
            const SizedBox(width: 8),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '$label: ',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    TextSpan(text: value),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (p.movesDay) {
      add(Icons.event, 'Día', '${_day(p.oldDay)} → ${_day(p.newDay)}');
    }
    if (c.containsKey('from_minutes') || c.containsKey('to_minutes')) {
      final from = c['from_minutes'];
      final to = c['to_minutes'];
      add(
        Icons.access_time,
        'Hora',
        '${from != null ? _hm(from) : 'igual'} – ${to != null ? _hm(to) : 'igual'}',
      );
    }
    if (c.containsKey('title')) add(Icons.title, 'Título', '${c['title']}');
    if (c.containsKey('description')) {
      final d = '${c['description']}';
      add(Icons.notes, 'Descripción', d.isEmpty ? '(vacía)' : d);
    }
    if (c.containsKey('category') || c.containsKey('tipo')) {
      add(
        Icons.category_outlined,
        'Categoría',
        [c['category'], c['tipo']].whereType<String>().join(' · '),
      );
    }
    if (p.addSharedWith.isNotEmpty) {
      final names = p.addSharedNames.isNotEmpty
          ? p.addSharedNames.join(', ')
          : '${p.addSharedWith.length} persona(s)';
      add(Icons.group_add_outlined, 'Compartir también con', names);
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final p = proposal;
    return AlertDialog(
      title: const Text('Cambio propuesto'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${p.whoLabel} propone cambiar tu evento «${p.eventTitle}»:',
              style: const TextStyle(fontSize: 15),
            ),
            const SizedBox(height: 10),
            ..._rows(),
            const SizedBox(height: 8),
            Text(
              'Si aceptas, el cambio llegará a todas las personas con las '
              'que compartes el evento.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Más tarde'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Rechazar', style: TextStyle(color: Colors.red)),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Aceptar'),
        ),
      ],
    );
  }
}
