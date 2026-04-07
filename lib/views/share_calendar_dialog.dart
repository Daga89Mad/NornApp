// lib/views/share_calendar_dialog.dart

import 'package:flutter/material.dart';
import '../models/friend_model.dart';
import '../core/friend_repository.dart';
import '../core/calendar_share_service.dart';

class ShareCalendarDialog extends StatefulWidget {
  const ShareCalendarDialog({Key? key}) : super(key: key);

  @override
  State<ShareCalendarDialog> createState() => _ShareCalendarDialogState();
}

class _ShareCalendarDialogState extends State<ShareCalendarDialog> {
  static const List<_CategoryOption> _categories = [
    _CategoryOption(
      key: 'trabajo',
      label: 'Trabajo',
      icon: Icons.work_outline,
      color: Colors.blue,
    ),
    _CategoryOption(
      key: 'eventos',
      label: 'Eventos',
      icon: Icons.celebration,
      color: Colors.amber,
    ),
    _CategoryOption(
      key: 'citas',
      label: 'Citas',
      icon: Icons.medical_services,
      color: Colors.orange,
    ),
    _CategoryOption(
      key: 'recordatorios',
      label: 'Recordatorios',
      icon: Icons.notifications_outlined,
      color: Colors.red,
    ),
    _CategoryOption(
      key: 'bebe',
      label: 'Bebé',
      icon: Icons.child_care,
      color: Colors.pink,
    ),
    _CategoryOption(
      key: 'periodo',
      label: 'Período',
      icon: Icons.favorite,
      color: Colors.deepPurple,
    ),
    _CategoryOption(
      key: 'turnos',
      label: 'Turnos',
      icon: Icons.work_history,
      color: Colors.teal,
    ),
  ];

  final Set<String> _selectedCategories = {
    'trabajo',
    'eventos',
    'citas',
    'recordatorios',
  };

  List<FriendModel> _friends = [];
  final Set<String> _selectedFriends = {};
  bool _loadingFriends = true;
  bool _sharing = false;
  bool _friendDropdownOpen = false;

  @override
  void initState() {
    super.initState();
    _loadFriends();
  }

  Future<void> _loadFriends() async {
    final friends = await FriendRepository.instance.getAll();
    if (mounted) {
      setState(() {
        _friends = friends;
        _loadingFriends = false;
      });
    }
  }

  // ── Compartir ──────────────────────────────────────────────────────────────

  Future<void> _share() async {
    if (_selectedCategories.isEmpty || _selectedFriends.isEmpty) return;

    setState(() => _sharing = true);

    final selectedFriendsList = _friends
        .where((f) => f.id != null && _selectedFriends.contains(f.id))
        .toList();

    try {
      await CalendarShareService.instance.shareWithFriends(
        categories: List<String>.from(_selectedCategories),
        friends: selectedFriendsList,
      );

      if (!mounted) return;
      Navigator.of(context).pop({'shared': true});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Calendario compartido con '
            '${selectedFriendsList.map((f) => f.displayName).join(', ')}',
          ),
          backgroundColor: Colors.green.shade600,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error al compartir: $e')));
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  String _friendsLabel() {
    if (_selectedFriends.isEmpty) return 'Selecciona amigos';
    final names = _friends
        .where((f) => f.id != null && _selectedFriends.contains(f.id))
        .map((f) => f.displayName)
        .toList();
    if (names.isEmpty) return 'Selecciona amigos';
    if (names.length <= 2) return names.join(', ');
    return '${names.take(2).join(', ')} +${names.length - 2}';
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cabecera
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.share_outlined, color: Colors.blue),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Compartir calendario',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Categorías
            const Text(
              'Categorías a compartir',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.black54,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _categories.map((cat) {
                final selected = _selectedCategories.contains(cat.key);
                return GestureDetector(
                  onTap: () => setState(() {
                    if (selected)
                      _selectedCategories.remove(cat.key);
                    else
                      _selectedCategories.add(cat.key);
                  }),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      color: selected
                          ? cat.color.withOpacity(0.12)
                          : Colors.grey.shade100,
                      border: Border.all(
                        color: selected ? cat.color : Colors.grey.shade300,
                        width: selected ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 150),
                          child: Icon(
                            selected
                                ? Icons.check_circle
                                : Icons.circle_outlined,
                            key: ValueKey(selected),
                            size: 15,
                            color: selected ? cat.color : Colors.grey.shade400,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Icon(
                          cat.icon,
                          size: 14,
                          color: selected ? cat.color : Colors.grey.shade500,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          cat.label,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: selected
                                ? FontWeight.w600
                                : FontWeight.normal,
                            color: selected ? cat.color : Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
            const Divider(height: 1),
            const SizedBox(height: 16),

            // Amigos
            const Text(
              'Compartir con',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.black54,
              ),
            ),
            const SizedBox(height: 8),

            if (_loadingFriends)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else if (_friends.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(
                    children: [
                      Icon(
                        Icons.group_outlined,
                        size: 40,
                        color: Colors.grey.shade300,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Sin amigos todavía',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade400,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    onTap: () => setState(
                      () => _friendDropdownOpen = !_friendDropdownOpen,
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _friendDropdownOpen
                              ? Colors.blue.shade400
                              : Colors.grey.shade300,
                          width: _friendDropdownOpen ? 1.5 : 1,
                        ),
                        color: Colors.white,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.people_outline,
                            size: 18,
                            color: Colors.grey.shade600,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _friendsLabel(),
                              style: TextStyle(
                                fontSize: 14,
                                color: _selectedFriends.isEmpty
                                    ? Colors.grey.shade400
                                    : Colors.black87,
                              ),
                            ),
                          ),
                          Icon(
                            _friendDropdownOpen
                                ? Icons.expand_less
                                : Icons.expand_more,
                            color: Colors.grey.shade500,
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_friendDropdownOpen)
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      constraints: const BoxConstraints(maxHeight: 180),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.shade200),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.08),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        itemCount: _friends.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1, indent: 52),
                        itemBuilder: (_, i) {
                          final friend = _friends[i];
                          final selected =
                              friend.id != null &&
                              _selectedFriends.contains(friend.id);
                          return ListTile(
                            dense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                            ),
                            leading: Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                color: selected
                                    ? Colors.blue.shade50
                                    : Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Center(
                                child: Text(
                                  friend.logo,
                                  style: const TextStyle(fontSize: 18),
                                ),
                              ),
                            ),
                            title: Text(
                              friend.displayName,
                              style: const TextStyle(fontSize: 14),
                            ),
                            subtitle: Text(
                              friend.email,
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade500,
                              ),
                            ),
                            trailing: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 150),
                              child: Icon(
                                selected
                                    ? Icons.check_circle
                                    : Icons.check_circle_outline,
                                key: ValueKey(selected),
                                color: selected
                                    ? Colors.blue
                                    : Colors.grey.shade300,
                                size: 20,
                              ),
                            ),
                            onTap: () {
                              if (friend.id == null) return;
                              setState(() {
                                if (selected)
                                  _selectedFriends.remove(friend.id);
                                else
                                  _selectedFriends.add(friend.id!);
                              });
                            },
                          );
                        },
                      ),
                    ),
                ],
              ),

            const SizedBox(height: 20),

            // Botón compartir
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed:
                    (_selectedCategories.isEmpty ||
                        _selectedFriends.isEmpty ||
                        _sharing)
                    ? null
                    : _share,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: _sharing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.send_outlined),
                label: Text(
                  _sharing
                      ? 'Compartiendo...'
                      : _selectedFriends.isEmpty
                      ? 'Selecciona al menos un amigo'
                      : _selectedCategories.isEmpty
                      ? 'Selecciona al menos una categoría'
                      : 'Compartir',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryOption {
  final String key;
  final String label;
  final IconData icon;
  final Color color;
  const _CategoryOption({
    required this.key,
    required this.label,
    required this.icon,
    required this.color,
  });
}
