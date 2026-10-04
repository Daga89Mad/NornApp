// lib/views/delete_series_dialog.dart
//
// Pregunta común al borrar algo que se repite (tareas, menús, entrenamientos,
// eventos del calendario y periodos de gastos):
//
//   ┌──────────────────────────────────────┐
//   │ Borrar «Gimnasio»                    │
//   │ Se repite 12 veces. ¿Qué quieres     │
//   │ borrar?                              │
//   │ [ Solo esta tarea                  ] │
//   │ [ Toda la serie (12)               ] │
//   │                           Cancelar   │
//   └──────────────────────────────────────┘
//
// Uso:
//   final scope = await askDeleteScopeIfSeries(context,
//       title: task.title, count: ids.length, onlyLabel: 'Solo esta tarea');
//   if (scope == null) return;                 // cancelado
//   if (scope == DeleteScope.series) { ... } else { ... }

import 'package:flutter/material.dart';

enum DeleteScope { one, series }

/// Si [count] > 1 pregunta si borrar solo este elemento o toda la serie.
/// Si no es una serie (count <= 1) devuelve [DeleteScope.one] sin preguntar.
/// Devuelve null si el usuario cancela.
Future<DeleteScope?> askDeleteScopeIfSeries(
  BuildContext context, {
  required String title,
  required int count,
  String onlyLabel = 'Solo este',
  String? message,
  String? detail,
}) async {
  if (count <= 1) return DeleteScope.one;
  return askDeleteScope(
    context,
    title: title,
    count: count,
    onlyLabel: onlyLabel,
    message: message,
    detail: detail,
  );
}

/// Pregunta si borrar solo este elemento o las [count] repeticiones de su
/// serie. [message] sustituye al texto "Se repite N veces…" y [detail] añade
/// una aclaración debajo. Devuelve null si el usuario cancela.
Future<DeleteScope?> askDeleteScope(
  BuildContext context, {
  required String title,
  required int count,
  String onlyLabel = 'Solo este',
  String? message,
  String? detail,
}) {
  final name = title.trim().isEmpty ? 'elemento' : '«${title.trim()}»';
  return showDialog<DeleteScope>(
    context: context,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      return AlertDialog(
        title: Text('Borrar $name'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(message ?? 'Se repite $count veces. ¿Qué quieres borrar?'),
            if (detail != null && detail.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(detail, style: theme.textTheme.bodySmall),
            ],
            const SizedBox(height: 18),
            OutlinedButton.icon(
              icon: const Icon(Icons.event_busy_outlined),
              label: Text(onlyLabel),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: () => Navigator.pop(ctx, DeleteScope.one),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              icon: const Icon(Icons.delete_sweep_outlined),
              label: Text('Toda la serie ($count)'),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red.shade600,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: () => Navigator.pop(ctx, DeleteScope.series),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
        ],
      );
    },
  );
}
