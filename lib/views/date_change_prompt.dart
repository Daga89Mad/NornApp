// lib/views/date_change_prompt.dart
//
// Diálogo que se muestra al entrar en Tareas / Menús / Entrenamiento cuando
// alguien ha movido de día un item compartido y falta mi respuesta.

import 'dart:async';
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
      // scrollable evita que el contenido desborde con fuentes grandes.
      scrollable: true,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
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
                Flexible(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Ahora',
                        style: TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _fmtDia(change.oldDay),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.lineThrough,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Icon(Icons.arrow_forward, size: 18, color: accent),
                ),
                Flexible(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Propuesto',
                        style: TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _fmtDia(change.newDay),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: accent,
                        ),
                      ),
                    ],
                  ),
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
          const SizedBox(height: 16),

          // ── Botonera propia (NO en `actions`) ──────────────────────────────
          // Así no depende del OverflowBar de AlertDialog y "Aceptar" nunca
          // se queda fuera del diálogo por falta de ancho.
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: accent,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: () => Navigator.pop<bool?>(context, true),
              icon: const Icon(Icons.check, color: Colors.white, size: 18),
              label: const Text(
                'Aceptar el cambio',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.redAccent,
                side: const BorderSide(color: Colors.redAccent),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: () => Navigator.pop<bool?>(context, false),
              icon: const Icon(Icons.close, size: 18),
              label: const Text('Rechazar'),
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () => Navigator.pop<bool?>(context, null),
              child: const Text(
                'Decidir más tarde',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          ),
        ],
      ),
      // Vacío a propósito: la botonera va en el content.
      actions: const [],
      actionsPadding: EdgeInsets.zero,
    );
  }
}

/// Botón de la barra superior con el número de propuestas pendientes.
///
/// Sirve para dos cosas: que no dependa de pillar el diálogo al vuelo (si se
/// pulsa "Más tarde" la propuesta sigue accesible aquí) y para poder ver de un
/// vistazo si este dispositivo está recibiendo algo.
class PendingDateChangesButton extends StatefulWidget {
  final String type; // 'tasks' | 'menus' | 'trainings'
  final Color accent;
  final VoidCallback? onResolved;

  const PendingDateChangesButton({
    super.key,
    required this.type,
    required this.accent,
    this.onResolved,
  });

  @override
  State<PendingDateChangesButton> createState() =>
      _PendingDateChangesButtonState();
}

class _PendingDateChangesButtonState extends State<PendingDateChangesButton> {
  int _count = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _refresh();
    // Sondeo ligero: el espejo local lo actualiza el listener del servicio.
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final n = await DateChangeService.instance.pendingCount(widget.type);
    if (mounted && n != _count) setState(() => _count = n);
  }

  Future<void> _open() async {
    if (_count == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No hay cambios de día pendientes de responder.'),
        ),
      );
      return;
    }
    final answered = await showPendingDateChanges(
      context,
      widget.type,
      accent: widget.accent,
    );
    await _refresh();
    if (answered) widget.onResolved?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        IconButton(
          tooltip: 'Cambios de día propuestos',
          icon: const Icon(Icons.event_repeat),
          onPressed: _open,
        ),
        if (_count > 0)
          Positioned(
            top: 6,
            right: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.redAccent,
                borderRadius: BorderRadius.circular(9),
              ),
              constraints: const BoxConstraints(minWidth: 16),
              child: Text(
                '$_count',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
