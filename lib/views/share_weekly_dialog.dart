// lib/views/share_weekly_dialog.dart
//
// Diálogo para compartir Menús semanales y/o Tareas semanales con amigos.
// Muy similar en estructura al ShareCalendarDialog ya existente.

import 'package:flutter/material.dart';
import '../models/friend_model.dart';
import '../core/friend_repository.dart';
import '../core/weekly_share_service.dart';

class ShareWeeklyDialog extends StatefulWidget {
  /// Si se pasa, pre-selecciona ese tipo ('menus' o 'tasks').
  final String? initialType;

  const ShareWeeklyDialog({Key? key, this.initialType}) : super(key: key);

  @override
  State<ShareWeeklyDialog> createState() => _ShareWeeklyDialogState();
}

class _ShareWeeklyDialogState extends State<ShareWeeklyDialog> {
  static const _menuType = 'menus';
  static const _taskType = 'tasks';

  static const _typeOptions = [
    _TypeOption(
      key: _menuType,
      label: 'Menú semanal',
      icon: Icons.restaurant_menu,
      color: Color(0xFF5C6BC0),
    ),
    _TypeOption(
      key: _taskType,
      label: 'Tareas semanales',
      icon: Icons.checklist_rtl,
      color: Color(0xFF00897B),
    ),
  ];

  late Set<String> _selectedTypes;
  List<FriendModel> _friends = [];
  final Set<String> _selectedFriends = {};
  bool _loadingFriends = true;
  bool _sharing = false;
  bool _friendDropdownOpen = false;

  // Para mostrar con quién ya está compartido actualmente
  List<Map<String, dynamic>> _currentShares = [];
  bool _loadingShares = true;

  @override
  void initState() {
    super.initState();
    _selectedTypes = widget.initialType != null
        ? {widget.initialType!}
        : {_menuType, _taskType};
    _loadFriends();
  }

  Future<void> _loadFriends() async {
    final friends = await FriendRepository.instance.getAll();
    if (!mounted) return;
    setState(() {
      _friends = friends;
      _loadingFriends = false;
    });
    _loadCurrentShares(friends);
  }

  Future<void> _loadCurrentShares(List<FriendModel> friends) async {
    final shares = await WeeklyShareService.instance.getCurrentShares(friends);
    if (!mounted) return;
    setState(() {
      _currentShares = shares;
      _loadingShares = false;
    });
  }

  // ══════════════════════════════════════════════════════════════════════════
  // ACCIONES
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> _share() async {
    if (_selectedTypes.isEmpty || _selectedFriends.isEmpty) return;
    setState(() => _sharing = true);

    final selectedFriendsList = _friends
        .where((f) => f.id != null && _selectedFriends.contains(f.id))
        .toList();

    try {
      await WeeklyShareService.instance.shareWithFriends(
        types: List<String>.from(_selectedTypes),
        friends: selectedFriendsList,
      );
      if (!mounted) return;
      Navigator.of(context).pop({'shared': true});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Compartido con ${selectedFriendsList.map((f) => f.displayName).join(', ')}',
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

  Future<void> _unshare(FriendModel friend, List<String> types) async {
    try {
      await WeeklyShareService.instance.unshareWithFriends(
        types: types,
        friends: [friend],
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Dejado de compartir con ${friend.displayName}'),
          backgroundColor: Colors.orange.shade700,
        ),
      );
      _loadCurrentShares(_friends);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ══════════════════════════════════════════════════════════════════════════

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

  String _typesLabel(List<String> types) {
    if (types.isEmpty) return '';
    return types.map((t) => t == _menuType ? 'Menú' : 'Tareas').join(' y ');
  }

  // ══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Cabecera ──────────────────────────────────────────────────
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFF5C6BC0).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.share_outlined,
                    color: Color(0xFF5C6BC0),
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Compartir con amigos',
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

            // ── Qué compartir ─────────────────────────────────────────────
            const Text(
              'Qué compartir',
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
              children: _typeOptions.map((opt) {
                final selected = _selectedTypes.contains(opt.key);
                return GestureDetector(
                  onTap: () => setState(() {
                    if (selected) {
                      _selectedTypes.remove(opt.key);
                    } else {
                      _selectedTypes.add(opt.key);
                    }
                  }),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      color: selected
                          ? opt.color.withOpacity(0.12)
                          : Colors.grey.shade100,
                      border: Border.all(
                        color: selected ? opt.color : Colors.grey.shade300,
                        width: selected ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          opt.icon,
                          size: 16,
                          color: selected ? opt.color : Colors.grey.shade500,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          opt.label,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: selected
                                ? FontWeight.w600
                                : FontWeight.normal,
                            color: selected ? opt.color : Colors.grey.shade600,
                          ),
                        ),
                        if (selected) ...[
                          const SizedBox(width: 6),
                          Icon(Icons.check_circle, size: 14, color: opt.color),
                        ],
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),

            // ── Selector de amigos ─────────────────────────────────────────
            const Text(
              'Con quién compartir',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.black54,
              ),
            ),
            const SizedBox(height: 10),

            if (_loadingFriends)
              const Center(child: CircularProgressIndicator())
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
                  // Dropdown selector de amigos
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
                              ? const Color(0xFF5C6BC0)
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
                                    ? const Color(0xFF5C6BC0).withOpacity(0.12)
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
                                    ? const Color(0xFF5C6BC0)
                                    : Colors.grey.shade300,
                                size: 20,
                              ),
                            ),
                            onTap: () {
                              if (friend.id == null) return;
                              setState(() {
                                if (selected) {
                                  _selectedFriends.remove(friend.id);
                                } else {
                                  _selectedFriends.add(friend.id!);
                                }
                              });
                            },
                          );
                        },
                      ),
                    ),
                ],
              ),

            const SizedBox(height: 20),

            // ── Compartir actualmente ──────────────────────────────────────
            if (!_loadingShares && _currentShares.isNotEmpty) ...[
              const Divider(),
              const SizedBox(height: 8),
              const Text(
                'Compartiendo actualmente',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.black54,
                ),
              ),
              const SizedBox(height: 8),
              ..._currentShares.map((share) {
                final friend = share['friend'] as FriendModel;
                final types = List<String>.from(share['types'] as List);
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.green.shade200),
                  ),
                  child: Row(
                    children: [
                      Text(friend.logo, style: const TextStyle(fontSize: 20)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              friend.displayName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                            Text(
                              _typesLabel(types),
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: () => _showUnshareConfirm(friend, types),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.redAccent,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text(
                          'Dejar',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 8),
            ],

            // ── Botón compartir ────────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed:
                    (_selectedTypes.isEmpty ||
                        _selectedFriends.isEmpty ||
                        _sharing)
                    ? null
                    : _share,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF5C6BC0),
                  foregroundColor: Colors.white,
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
                      : _selectedTypes.isEmpty
                      ? 'Selecciona qué compartir'
                      : 'Compartir',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showUnshareConfirm(
    FriendModel friend,
    List<String> types,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Dejar de compartir'),
        content: Text(
          '¿Dejar de compartir ${_typesLabel(types)} con ${friend.displayName}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Dejar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm == true) await _unshare(friend, types);
  }
}

class _TypeOption {
  final String key;
  final String label;
  final IconData icon;
  final Color color;

  const _TypeOption({
    required this.key,
    required this.label,
    required this.icon,
    required this.color,
  });
}
