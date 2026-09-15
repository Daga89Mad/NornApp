// lib/views/date_change_prompt.dart
//
// Diálogo que se muestra al entrar en Tareas / Menús / Entrenamiento cuando
// alguien ha movido de día un item compartido y falta mi respuesta.

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../core/date_change_service.dart';

const _diasCortosPrompt = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
const _mesesPrompt = [
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

String _fmtDia(DateTime d) =>
    '${_diasCortosPrompt[d.weekday - 1]} ${d.day} ${_mesesPrompt[d.month]}';

// Evita que se apilen varios diálogos si el listener dispara mientras uno
// ya está abierto.
bool _promptOpen = false;

/// Muestra, una a una, las propuestas de cambio de día pendientes de [type]
/// ('tasks' | 'menus' | 'trainings').
///
/// Devuelve true si se ha respondido a alguna, para que la pantalla recargue.
Future<bool> showPendingDateChanges(
  BuildContext context,
  String type, {
  Color accent = const Color(0xFF00897B),
}) async {
  if (_promptOpen) return false;

  final pending = await DateChangeService.instance.pendingForType(type);
  if (pending.isEmpty || !context.mounted) return false;

  _promptOpen = true;
  bool answeredAny = false;

  try {
    for (final change in pending) {
      if (!context.mounted) break;

      final bool? accepted = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _DateChangeDialog(change: change, accent: accent),
      );

      // null = "Más tarde": la propuesta sigue pendiente para la próxima vez.
      if (accepted == null) break;

      if (accepted) {
        await DateChangeService.instance.accept(change);
      } else {
        await DateChangeService.instance.reject(change);
      }
      answeredAny = true;
    }
  } finally {
    _promptOpen = false;
  }

  return answeredAny;
}

class _DateChangeDialog extends StatelessWidget {
  final PendingDateChange change;
  final Color accent;

  const _DateChangeDialog({required this.change, required this.accent});

  @override
  Widget build(BuildContext context) {
    final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final bool soyDueno = change.ownerId.isNotEmpty && change.ownerId == myUid;

    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      title: Row(
        children: [
          Icon(Icons.event_repeat, color: accent, size: 22),
          const SizedBox(width: 8),
          const Expanded(child: Text('Cambio de día propuesto')),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: change.whoLabel,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                TextSpan(text: ' quiere mover ${change.typeLabel} '),
                TextSpan(
                  text: '“${change.itemTitle}”',
                  style: const TextStyle(fontStyle: FontStyle.italic),
                ),
                const TextSpan(text: ' a otro día.'),
              ],
            ),
            style: const TextStyle(fontSize: 14, height: 1.35),
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: accent.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: accent.withOpacity(0.3)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Ahora',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _fmtDia(change.oldDay),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.lineThrough,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
                Icon(Icons.arrow_forward, size: 18, color: accent),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Propuesto',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _fmtDia(change.newDay),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: accent,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            soyDueno
                ? 'Eres el dueño: si aceptas, se moverá para todos.'
                : 'Si aceptas, se moverá solo en tu calendario.',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop<bool?>(context, null),
          child: const Text('Más tarde', style: TextStyle(color: Colors.grey)),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
              onPressed: () => Navigator.pop<bool?>(context, false),
              child: const Text(
                'Rechazar',
                style: TextStyle(color: Colors.redAccent),
              ),
            ),
            const SizedBox(width: 4),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: accent),
              onPressed: () => Navigator.pop<bool?>(context, true),
              child: const Text(
                'Aceptar',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
