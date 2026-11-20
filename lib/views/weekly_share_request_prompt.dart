// lib/views/weekly_share_request_prompt.dart
//
// Diálogo para que el DUEÑO de una tarea (o menú/entrenamiento) semanal acepte
// o rechace que otra persona con la que la comparte la comparta con más gente.

import 'package:flutter/material.dart';
import '../core/weekly_share_request_service.dart';
import '../core/weekly_share_service.dart';
import '../core/friend_repository.dart';
import 'share_with_picker.dart';

bool _shareRequestPromptOpen = false;

/// Muestra una a una las peticiones pendientes sobre mis elementos de [type].
/// Devuelve true si se ha aceptado alguna (para recargar la pantalla).
Future<bool> showPendingShareRequests(
  BuildContext context,
  String type, {
  Color? accent,
}) async {
  if (_shareRequestPromptOpen) return false;
  final pending = await WeeklyShareRequestService.instance.pendingForMe(type);
  if (pending.isEmpty || !context.mounted) return false;

  _shareRequestPromptOpen = true;
  bool acceptedAny = false;
  try {
    for (final r in pending) {
      if (!context.mounted) break;
      final bool? accepted = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _ShareRequestDialog(request: r, accent: accent),
      );
      if (accepted == null) break; // "Más tarde"
      if (accepted) {
        final ok = await WeeklyShareRequestService.instance.accept(r);
        acceptedAny = acceptedAny || ok;
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                ok
                    ? '«${r.itemTitle}» compartida con ${r.namesLabel}'
                    : 'No se pudo compartir',
              ),
            ),
          );
        }
      } else {
        await WeeklyShareRequestService.instance.reject(r);
      }
    }
  } finally {
    _shareRequestPromptOpen = false;
  }
  return acceptedAny;
}

class _ShareRequestDialog extends StatelessWidget {
  final WeeklyShareRequest request;
  final Color? accent;
  const _ShareRequestDialog({required this.request, this.accent});

  String get _what {
    switch (request.type) {
      case 'menus':
        return 'tu menú';
      case 'trainings':
        return 'tu entrenamiento';
      default:
        return 'tu tarea';
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = accent ?? Theme.of(context).colorScheme.primary;
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.person_add_alt, color: color),
          const SizedBox(width: 8),
          const Expanded(child: Text('Compartir con más gente')),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${request.whoLabel} quiere compartir $_what '
            '«${request.itemTitle}» con:',
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var i = 0; i < request.addSharedWith.length; i++)
                Chip(
                  avatar: const Icon(Icons.person_outline, size: 16),
                  label: Text(
                    i < request.addSharedNames.length &&
                            request.addSharedNames[i].trim().isNotEmpty
                        ? request.addSharedNames[i]
                        : 'Otra persona',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'Si aceptas, la verán en su semana (con sus subtareas).',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Más tarde'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text(
            'Rechazar',
            style: TextStyle(color: Colors.redAccent),
          ),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: color),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Aceptar', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
// PEDIR (lado de quien recibe el elemento compartido)
// ══════════════════════════════════════════════════════════════════════════

/// Bloque "Compartir también con" para el detalle de un elemento semanal
/// que es de otra persona. Muestra mis amigos sin preselección.
class ForeignShareSection extends StatelessWidget {
  final String type; // 'tasks' | 'menus' | 'trainings'
  final Color accent;
  final ValueChanged<Set<String>> onChanged;

  const ForeignShareSection({
    Key? key,
    required this.type,
    required this.accent,
    required this.onChanged,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        const Divider(),
        Row(
          children: const [
            Icon(Icons.person_add_alt, size: 18),
            SizedBox(width: 8),
            Text(
              'Compartir también con',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const Padding(
          padding: EdgeInsets.only(top: 2, left: 4, bottom: 4),
          child: Text(
            'Se le pedirá a quien lo creó; cuando acepte, '
            'les aparecerá en su semana.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ),
        ShareWithPicker(
          type: type,
          accent: accent,
          loadInitial: () async => <String>{},
          notifyInitial: false,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

/// Envía al dueño la petición de compartir con [uids] y avisa con un
/// SnackBar en [context]. Devuelve true si se ha enviado.
Future<bool> sendForeignShareRequest(
  BuildContext context, {
  required String type,
  required String itemId,
  required String itemTitle,
  required String ownerId,
  required String ownerName,
  required String sharedWithJson,
  required Set<String> uids,
}) async {
  if (uids.isEmpty) return false;
  final friends = await FriendRepository.instance.getAll();
  final list = uids.toList();
  final names = list.map((uid) {
    for (final f in friends) {
      if (f.firebaseUid == uid) return f.displayName;
    }
    return '';
  }).toList();

  final ok = await WeeklyShareRequestService.instance.request(
    type: type,
    itemId: itemId,
    itemTitle: itemTitle,
    ownerId: ownerId,
    uids: list,
    names: names,
    alreadyShared: WeeklyShareService.parseUids(sharedWithJson),
  );
  if (context.mounted) {
    final owner = ownerName.isNotEmpty ? ownerName : 'quien lo creó';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Petición enviada a $owner. Se compartirá cuando la acepte.'
              : 'Ya lo tienen todas esas personas',
        ),
      ),
    );
  }
  return ok;
}
