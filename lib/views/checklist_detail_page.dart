// lib/views/checklist_detail_page.dart

import 'package:flutter/material.dart';
import '../models/event_item.dart';
import '../models/checklist_item.dart';
import '../core/checklist_repository.dart';
import '../core/event_repository.dart';
import 'day_view.dart'; // AddEventDialog

class ChecklistDetailPage extends StatefulWidget {
  final EventItem event;
  final DateTime date; // necesario para guardar edición

  const ChecklistDetailPage({Key? key, required this.event, required this.date})
    : super(key: key);

  @override
  State<ChecklistDetailPage> createState() => _ChecklistDetailPageState();
}

class _ChecklistDetailPageState extends State<ChecklistDetailPage> {
  late EventItem _event; // copia mutable local
  List<ChecklistItem> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _event = widget.event;
    _loadItems();
  }

  Future<void> _loadItems() async {
    if (_event.id == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final items = await ChecklistRepository.instance.getItemsForEvent(
        _event.id!,
      );
      if (mounted) setState(() => _items = items);
    } catch (e) {
      debugPrint('Error cargando checklist: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Toggle item ────────────────────────────────────────────────────────────

  Future<void> _toggleItem(int index) async {
    final item = _items[index];
    if (item.id == null) return;
    final newValue = !item.isChecked;
    setState(() => _items[index] = item.copyWith(isChecked: newValue));
    try {
      await ChecklistRepository.instance.updateChecked(item.id!, newValue);
    } catch (e) {
      if (mounted) setState(() => _items[index] = item); // revertir
      debugPrint('Error actualizando item: $e');
    }
  }

  // ── Editar ─────────────────────────────────────────────────────────────────

  Future<void> _openEdit() async {
    // Prerrellenar el diálogo con los datos actuales
    final existingItemTexts = _items.map((i) => i.text).toList();

    final result = await showDialog<Map<String, dynamic>?>(
      context: context,
      builder: (_) => AddEventDialog(
        initialEvent: _event,
        initialChecklistItems: existingItemTexts,
      ),
    );
    if (result == null || !mounted) return;

    // Construir evento actualizado
    final categoryStr = result['category'] as String? ?? 'Eventos';
    final category = EventRepository.categoryFromString(categoryStr);
    final tipo = (result['tipo'] as Tipo?) ?? Tipo.Otros;

    final updatedEvent = EventItem(
      id: _event.id,
      category: category,
      tipo: tipo,
      title: result['title'] as String,
      description: (result['description'] as String?) ?? '',
      icon: EventRepository.iconForCategory(category),
      creator: _event.creator,
      users: _event.users,
      from: result['start'] as TimeOfDay,
      to: result['end'] as TimeOfDay,
      color: EventRepository.colorForCategory(category),
    );

    try {
      final saved = await EventRepository.instance.save(
        updatedEvent,
        widget.date,
      );

      if (saved.id != null) {
        if (tipo == Tipo.Checklist) {
          final items = (result['checklistItems'] as List<String>?) ?? [];
          await ChecklistRepository.instance.saveAll(saved.id!, items);
        } else {
          // Ya no es Checklist → borrar items
          await ChecklistRepository.instance.deleteAllForEvent(saved.id!);
        }
      }

      if (mounted) {
        setState(() => _event = saved);
        await _loadItems();
      }
    } catch (e) {
      debugPrint('Error guardando edición: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error al guardar: $e')));
      }
    }
  }

  // ── Borrar ─────────────────────────────────────────────────────────────────

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Borrar evento'),
        content: Text('¿Borrar "${_event.title}" y todos sus items?'),
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
    if (confirmed != true || !mounted) return;

    try {
      if (_event.id != null) {
        await ChecklistRepository.instance.deleteAllForEvent(_event.id!);
        await EventRepository.instance.delete(_event.id!);
      }
      if (mounted) Navigator.of(context).pop({'action': 'deleted'});
    } catch (e) {
      debugPrint('Error borrando evento: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error al borrar: $e')));
      }
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final ev = _event;
    final completed = _items.where((i) => i.isChecked).length;
    final total = _items.length;
    final progress = total == 0 ? 0.0 : completed / total;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Text(ev.icon, style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 8),
            Expanded(child: Text(ev.title, overflow: TextOverflow.ellipsis)),
          ],
        ),
        actions: [
          // ── Editar ────────────────────────────────────────────────────────
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Editar evento',
            onPressed: _openEdit,
          ),
          // ── Borrar ────────────────────────────────────────────────────────
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
            tooltip: 'Borrar evento',
            onPressed: _confirmDelete,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // ── Cabecera ──────────────────────────────────────────────────
                Container(
                  color: ev.color.withOpacity(0.08),
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.access_time, size: 16, color: ev.color),
                          const SizedBox(width: 6),
                          Text(
                            '${ev.from.format(context)} — ${ev.to.format(context)}',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ],
                      ),
                      if (ev.description.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          ev.description,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      // ── Barra de progreso ──────────────────────────────────
                      Row(
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: progress,
                                minHeight: 8,
                                backgroundColor: Colors.grey.shade200,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  ev.color,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            '$completed / $total',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: ev.color,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // ── Lista de items ────────────────────────────────────────────
                Expanded(
                  child: _items.isEmpty
                      ? Center(
                          child: Text(
                            'Sin items en este checklist',
                            style: TextStyle(color: Colors.grey.shade500),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: _items.length,
                          separatorBuilder: (_, __) =>
                              const Divider(height: 1, indent: 56),
                          itemBuilder: (context, index) {
                            final item = _items[index];
                            return ListTile(
                              leading: GestureDetector(
                                onTap: () => _toggleItem(index),
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 200),
                                  child: Icon(
                                    item.isChecked
                                        ? Icons.check_box
                                        : Icons.check_box_outline_blank,
                                    key: ValueKey(item.isChecked),
                                    color: item.isChecked
                                        ? ev.color
                                        : Colors.grey.shade400,
                                    size: 26,
                                  ),
                                ),
                              ),
                              title: Text(
                                item.text,
                                style: TextStyle(
                                  fontSize: 15,
                                  decoration: item.isChecked
                                      ? TextDecoration.lineThrough
                                      : null,
                                  color: item.isChecked
                                      ? Colors.grey.shade400
                                      : null,
                                ),
                              ),
                              onTap: () => _toggleItem(index),
                            );
                          },
                        ),
                ),

                // ── Pie ───────────────────────────────────────────────────────
                if (total > 0)
                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      child: Text(
                        completed == total
                            ? '✅ ¡Checklist completado!'
                            : 'Quedan ${total - completed} items por completar',
                        style: TextStyle(
                          fontSize: 13,
                          color: completed == total
                              ? Colors.green.shade700
                              : Colors.grey.shade600,
                          fontWeight: FontWeight.w500,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
