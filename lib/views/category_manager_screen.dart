// lib/views/category_manager_screen.dart
import 'package:flutter/material.dart';
import '../models/calendar_category.dart';
import '../core/category_repository.dart';

class CategoryManagerScreen extends StatefulWidget {
  const CategoryManagerScreen({Key? key}) : super(key: key);

  @override
  State<CategoryManagerScreen> createState() => _CategoryManagerScreenState();
}

class _CategoryManagerScreenState extends State<CategoryManagerScreen> {
  List<CalendarCategory> _custom = [];
  bool _loading = true;

  static const List<Color> _palette = [
    Color(0xFF2196F3),
    Color(0xFF3F51B5),
    Color(0xFF9C27B0),
    Color(0xFFE91E63),
    Color(0xFFF44336),
    Color(0xFFFF9800),
    Color(0xFFFFC107),
    Color(0xFF4CAF50),
    Color(0xFF009688),
    Color(0xFF00BCD4),
    Color(0xFF795548),
    Color(0xFF607D8B),
  ];

  static const List<String> _quickEmojis = [
    '🏷️',
    '🏋️',
    '🎓',
    '🛒',
    '🐶',
    '✈️',
    '🎵',
    '💊',
    '⚽',
    '🎂',
    '🏠',
    '💼',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final c = await CategoryRepository.instance.getCustom();
    if (!mounted) return;
    setState(() {
      _custom = c;
      _loading = false;
    });
  }

  Future<void> _openEditor({CalendarCategory? existing}) async {
    final result = await showDialog<_CategoryDraft>(
      context: context,
      builder: (_) => _CategoryEditorDialog(
        initial: existing,
        palette: _palette,
        quickEmojis: _quickEmojis,
      ),
    );
    if (result == null) return;

    if (existing == null) {
      await CategoryRepository.instance.create(
        label: result.label,
        color: result.color,
        icon: result.emoji,
      );
    } else {
      await CategoryRepository.instance.update(
        existing.copyWith(
          label: result.label,
          color: result.color,
          icon: result.emoji,
          synced: false,
        ),
      );
    }
    await _load();
  }

  Future<void> _delete(CalendarCategory cat) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Borrar categoría'),
        content: Text(
          'Se borrará "${cat.label}". Los eventos que la usaban seguirán '
          'existiendo, pero dejarán de mostrarse agrupados bajo ella.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Borrar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await CategoryRepository.instance.delete(cat.key);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Categorías')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.add),
        label: const Text('Nueva'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: [
                _sectionTitle('Personalizadas'),
                if (_custom.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'Aún no has creado categorías propias.',
                      style: TextStyle(color: Colors.grey.shade500),
                    ),
                  )
                else
                  ..._custom.map(
                    (c) => _tile(
                      c,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit_outlined, size: 20),
                            onPressed: () => _openEditor(existing: c),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 20),
                            color: Colors.red.shade400,
                            onPressed: () => _delete(c),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 20),
                _sectionTitle('Integradas'),
                ...CalendarCategory.builtIns().map(
                  (c) => _tile(
                    c,
                    trailing: Icon(
                      Icons.lock_outline,
                      size: 18,
                      color: Colors.grey.shade400,
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _sectionTitle(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      t,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: Colors.grey.shade600,
      ),
    ),
  );

  Widget _tile(CalendarCategory c, {required Widget trailing}) => Card(
    elevation: 0,
    color: Colors.grey.shade50,
    margin: const EdgeInsets.only(bottom: 8),
    child: ListTile(
      leading: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: c.color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: c.color.withOpacity(0.5), width: 1.5),
        ),
        child: Text(c.icon, style: const TextStyle(fontSize: 20)),
      ),
      title: Text(c.label, style: const TextStyle(fontWeight: FontWeight.w600)),
      trailing: trailing,
    ),
  );
}

// ── Borrador de categoría devuelto por el editor ──────────────────────────────
class _CategoryDraft {
  final String label;
  final Color color;
  final String emoji;
  const _CategoryDraft(this.label, this.color, this.emoji);
}

// ── Diálogo de crear/editar ───────────────────────────────────────────────────
class _CategoryEditorDialog extends StatefulWidget {
  final CalendarCategory? initial;
  final List<Color> palette;
  final List<String> quickEmojis;

  const _CategoryEditorDialog({
    required this.initial,
    required this.palette,
    required this.quickEmojis,
    Key? key,
  }) : super(key: key);

  @override
  State<_CategoryEditorDialog> createState() => _CategoryEditorDialogState();
}

class _CategoryEditorDialogState extends State<_CategoryEditorDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _emojiCtrl;
  late Color _color;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.initial?.label ?? '');
    _emojiCtrl = TextEditingController(text: widget.initial?.icon ?? '🏷️');
    _color = widget.initial?.color ?? widget.palette.first;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emojiCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.initial == null ? 'Nueva categoría' : 'Editar categoría',
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: 'Nombre'),
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 16),
            const Text(
              'Icono (emoji)',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _emojiCtrl,
              maxLength: 2,
              decoration: const InputDecoration(
                counterText: '',
                hintText: '🏷️',
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: widget.quickEmojis
                  .map(
                    (e) => GestureDetector(
                      onTap: () => setState(() => _emojiCtrl.text = e),
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(e, style: const TextStyle(fontSize: 18)),
                      ),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 16),
            const Text(
              'Color',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: widget.palette.map((c) {
                final sel = c.value == _color.value;
                return GestureDetector(
                  onTap: () => setState(() => _color = c),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: sel ? Colors.black87 : Colors.transparent,
                        width: 2.5,
                      ),
                    ),
                    child: sel
                        ? const Icon(Icons.check, color: Colors.white, size: 18)
                        : null,
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: () {
            final name = _nameCtrl.text.trim();
            final emoji = _emojiCtrl.text.trim().isEmpty
                ? '🏷️'
                : _emojiCtrl.text.trim();
            if (name.isEmpty) return;
            Navigator.pop(context, _CategoryDraft(name, _color, emoji));
          },
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}
