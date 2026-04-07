// lib/views/friends_screen.dart

import 'package:flutter/material.dart';
import '../models/friend_model.dart';
import '../models/friend_request_model.dart';
import '../core/friend_repository.dart';
import '../core/friend_request_repository.dart';
import '../core/firebase_sync_service.dart';
import 'package:firebase_auth/firebase_auth.dart';

// ── Categorías de logos ────────────────────────────────────────────────────────

const Map<String, List<String>> _logoCategories = {
  '😊 Personas': ['😊', '😄', '😎', '🥳', '🤩', '😇', '🥰', '😜', '🤓', '👑'],
  '🐾 Animales': [
    '🐶',
    '🐱',
    '🐭',
    '🐹',
    '🐰',
    '🦊',
    '🐻',
    '🐼',
    '🐨',
    '🐯',
    '🦁',
    '🐮',
    '🐷',
    '🐸',
    '🐵',
  ],
  '🚗 Vehículos': [
    '🚗',
    '🚕',
    '🏎',
    '🚙',
    '🚌',
    '🚎',
    '🚓',
    '🚑',
    '🚒',
    '✈️',
    '🚀',
    '⛵',
    '🏍',
    '🚲',
    '🛸',
  ],
  '🌿 Plantas': [
    '🌵',
    '🌲',
    '🌴',
    '🌱',
    '🌿',
    '🍀',
    '🎋',
    '🌸',
    '🌺',
    '🌻',
    '🌼',
    '🍁',
    '🍄',
    '🎄',
    '🌾',
  ],
  '🍎 Frutas': [
    '🍎',
    '🍐',
    '🍊',
    '🍋',
    '🍌',
    '🍉',
    '🍇',
    '🍓',
    '🫐',
    '🍒',
    '🍑',
    '🥭',
    '🍍',
    '🥥',
    '🍈',
  ],
  '⚽ Deportes': [
    '⚽',
    '🏀',
    '🎾',
    '🏐',
    '🏈',
    '⚾',
    '🏉',
    '🎱',
    '🏓',
    '🏸',
    '🥊',
    '🤿',
    '🎿',
    '⛷',
    '🤺',
  ],
  '🎵 Música': [
    '🎵',
    '🎸',
    '🎹',
    '🎺',
    '🎻',
    '🥁',
    '🎷',
    '🎤',
    '🎧',
    '🎼',
    '🎙',
    '📻',
    '🎚',
    '🎛',
    '🪗',
  ],
};

// ── Pantalla principal ─────────────────────────────────────────────────────────

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({Key? key}) : super(key: key);
  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  List<FriendModel> _friends = [];
  List<FriendRequestModel> _received = [];
  List<FriendRequestModel> _sent = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadAll();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    // Sincronizar solicitudes aceptadas para que el emisor vea al amigo
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      await FirebaseSyncService.instance.pullAcceptedRequests(uid);
    }
    final results = await Future.wait([
      FriendRepository.instance.getAll(),
      FriendRequestRepository.instance.getPendingReceived(),
      FriendRequestRepository.instance.getPendingSent(),
    ]);
    if (mounted) {
      setState(() {
        _friends = results[0] as List<FriendModel>;
        _received = results[1] as List<FriendRequestModel>;
        _sent = results[2] as List<FriendRequestModel>;
        _loading = false;
      });
    }
  }

  // ── Añadir amigo ───────────────────────────────────────────────────────────

  Future<void> _openAddFriend() async {
    final result = await showDialog<Map<String, dynamic>?>(
      context: context,
      builder: (_) => const _AddFriendDialog(),
    );
    if (result == null) return;

    final requestResult = await FriendRequestRepository.instance.sendRequest(
      toUid: result['uid'] as String,
      toEmail: result['email'] as String,
      fromLogo: result['logo'] as String,
    );

    if (!mounted) return;

    switch (requestResult) {
      case 'self':
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No puedes añadirte a ti mismo')),
        );
        break;
      case 'already_sent':
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ya enviaste una solicitud a este usuario'),
          ),
        );
        break;
      case 'already_friends':
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Ya sois amigos')));
        break;
      case null:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error al enviar la solicitud')),
        );
        break;
      default:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Solicitud enviada a ${result['email']}'),
            backgroundColor: Colors.green.shade600,
          ),
        );
        _tabController.animateTo(2); // ir a "Enviadas"
        _loadAll();
    }
  }

  // ── Borrar amigo ───────────────────────────────────────────────────────────

  Future<void> _deleteFriend(FriendModel friend) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Borrar amigo'),
        content: Text('¿Borrar a "${friend.displayName}"?'),
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
    if (confirmed != true || friend.id == null) return;
    await FriendRepository.instance.delete(friend.id!);
    _loadAll();
  }

  // ── Aceptar / rechazar solicitud ───────────────────────────────────────────

  Future<void> _acceptRequest(FriendRequestModel req) async {
    await FriendRequestRepository.instance.acceptRequest(req);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${req.fromName} añadido a tus amigos'),
          backgroundColor: Colors.green.shade600,
        ),
      );
    }
    _loadAll();
  }

  Future<void> _rejectRequest(FriendRequestModel req) async {
    await FriendRequestRepository.instance.rejectRequest(req);
    _loadAll();
  }

  Future<void> _cancelSent(FriendRequestModel req) async {
    if (req.id == null) return;
    await FriendRequestRepository.instance.cancelRequest(req.id!);
    _loadAll();
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final receivedBadge = _received.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Amigos'),
        elevation: 1,
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_outlined),
            tooltip: 'Añadir amigo',
            onPressed: _openAddFriend,
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadAll),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            const Tab(text: 'Amigos'),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Recibidas'),
                  if (receivedBadge > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$receivedBadge',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Tab(text: 'Enviadas'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddFriend,
        icon: const Icon(Icons.person_add_outlined),
        label: const Text('Añadir amigo'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildFriendsList(),
                _buildReceivedList(),
                _buildSentList(),
              ],
            ),
    );
  }

  // ── Tab 1: Lista de amigos ─────────────────────────────────────────────────

  Widget _buildFriendsList() {
    if (_friends.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('😶', style: TextStyle(fontSize: 56)),
            const SizedBox(height: 12),
            Text(
              'Sin amigos todavía',
              style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 6),
            Text(
              'Busca a alguien por su email para añadirle',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade400),
            ),
          ],
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      itemCount: _friends.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _FriendCard(
        friend: _friends[i],
        onDelete: () => _deleteFriend(_friends[i]),
      ),
    );
  }

  // ── Tab 2: Solicitudes recibidas ───────────────────────────────────────────

  Widget _buildReceivedList() {
    if (_received.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined, size: 56, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text(
              'Sin solicitudes pendientes',
              style: TextStyle(fontSize: 15, color: Colors.grey.shade500),
            ),
          ],
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      itemCount: _received.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final req = _received[i];
        return Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                // Avatar
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(
                      req.fromLogo,
                      style: const TextStyle(fontSize: 26),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        req.fromName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      Text(
                        req.fromEmail,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Quiere ser tu amigo',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.blue.shade600,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                // Acciones
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green.shade600,
                        minimumSize: const Size(80, 34),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                      onPressed: () => _acceptRequest(req),
                      child: const Text(
                        'Aceptar',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                    const SizedBox(height: 6),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                        minimumSize: const Size(80, 34),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                      onPressed: () => _rejectRequest(req),
                      child: const Text(
                        'Rechazar',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Tab 3: Solicitudes enviadas ────────────────────────────────────────────

  Widget _buildSentList() {
    if (_sent.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.send_outlined, size: 56, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text(
              'Sin solicitudes enviadas',
              style: TextStyle(fontSize: 15, color: Colors.grey.shade500),
            ),
          ],
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      itemCount: _sent.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final req = _sent[i];
        return Card(
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.orange.shade50,
              child: Icon(
                Icons.schedule,
                color: Colors.orange.shade400,
                size: 20,
              ),
            ),
            title: Text(
              req.toEmail,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
            subtitle: const Text(
              'Pendiente de aceptar',
              style: TextStyle(fontSize: 12, color: Colors.orange),
            ),
            trailing: IconButton(
              icon: const Icon(Icons.close, color: Colors.red, size: 20),
              tooltip: 'Cancelar solicitud',
              onPressed: () => _cancelSent(req),
            ),
          ),
        );
      },
    );
  }
}

// ── Tarjeta de amigo ───────────────────────────────────────────────────────────

class _FriendCard extends StatelessWidget {
  final FriendModel friend;
  final VoidCallback onDelete;
  const _FriendCard({required this.friend, required this.onDelete, Key? key})
    : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: Text(friend.logo, style: const TextStyle(fontSize: 26)),
          ),
        ),
        title: Text(
          friend.displayName,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (friend.alias.isNotEmpty)
              Text(
                friend.name,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
              ),
            Text(
              friend.email,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            ),
          ],
        ),
        isThreeLine: friend.alias.isNotEmpty,
        trailing: IconButton(
          icon: const Icon(
            Icons.delete_outline,
            size: 20,
            color: Colors.redAccent,
          ),
          onPressed: onDelete,
          tooltip: 'Borrar',
        ),
      ),
    );
  }
}

// ── Diálogo añadir amigo ───────────────────────────────────────────────────────

class _AddFriendDialog extends StatefulWidget {
  const _AddFriendDialog({Key? key}) : super(key: key);
  @override
  State<_AddFriendDialog> createState() => _AddFriendDialogState();
}

class _AddFriendDialogState extends State<_AddFriendDialog> {
  final _emailCtrl = TextEditingController();

  bool _searching = false;
  bool _found = false;
  String _foundName = '';
  String _foundEmail = '';
  String _foundUid = '';
  String _selectedLogo = '😊';
  String _selectedCat = '😊 Personas';
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _searchByEmail() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Introduce un email válido');
      return;
    }
    setState(() {
      _searching = true;
      _error = null;
      _found = false;
    });

    final result = await FriendRepository.instance.lookupByEmail(email);
    if (!mounted) return;

    if (result == null) {
      setState(() {
        _searching = false;
        _error =
            'No se encontró ningún usuario con ese email.\n'
            'Asegúrate de que está registrado en la app.';
      });
    } else {
      setState(() {
        _searching = false;
        _found = true;
        _foundUid = result['uid'] ?? '';
        _foundName = result['name'] ?? '';
        _foundEmail = result['email'] ?? email;
        _error = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 60),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Añadir amigo',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),

            // Búsqueda
            const Text(
              'Buscar por email',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.black54,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      hintText: 'email@ejemplo.com',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      isDense: true,
                      suffixIcon: _searching
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          : null,
                    ),
                    onSubmitted: (_) => _searchByEmail(),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _searching ? null : _searchByEmail,
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(80, 48),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  child: const Text('Buscar'),
                ),
              ],
            ),

            if (_error != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 16,
                      color: Colors.red.shade700,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error!,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.red.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            if (_found) ...[
              const SizedBox(height: 12),
              // Usuario encontrado
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.check_circle,
                      color: Colors.green.shade600,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _foundName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          Text(
                            _foundEmail,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Selector de logo
              const Text(
                'Elige un logo para identificarle',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.black54,
                ),
              ),
              const SizedBox(height: 8),

              Center(
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.blue.shade200, width: 2),
                  ),
                  child: Center(
                    child: Text(
                      _selectedLogo,
                      style: const TextStyle(fontSize: 34),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),

              // Categorías
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _logoCategories.keys.map((cat) {
                    final active = cat == _selectedCat;
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: GestureDetector(
                        onTap: () => setState(() => _selectedCat = cat),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            color: active
                                ? Colors.blue.shade600
                                : Colors.grey.shade100,
                            border: Border.all(
                              color: active
                                  ? Colors.blue.shade600
                                  : Colors.grey.shade300,
                            ),
                          ),
                          child: Text(
                            cat.split(' ').first,
                            style: TextStyle(fontSize: active ? 18 : 16),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 8),

              // Grid emojis
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: (_logoCategories[_selectedCat] ?? []).map((emoji) {
                    final sel = emoji == _selectedLogo;
                    return GestureDetector(
                      onTap: () => setState(() => _selectedLogo = emoji),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 120),
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: sel ? Colors.blue.shade100 : Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: sel
                                ? Colors.blue.shade400
                                : Colors.grey.shade200,
                            width: sel ? 2 : 1,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            emoji,
                            style: const TextStyle(fontSize: 22),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 16),

              // Info sobre la solicitud
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 16,
                      color: Colors.blue.shade600,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Se enviará una solicitud a $_foundName. '
                        'Hasta que la acepte no podréis compartir contenido.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.blue.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(null),
                  child: const Text('Cancelar'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(120, 44),
                  ),
                  onPressed: _found
                      ? () {
                          Navigator.of(context).pop({
                            'uid': _foundUid,
                            'email': _foundEmail,
                            'logo': _selectedLogo,
                          });
                        }
                      : null,
                  child: const Text('Enviar solicitud'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
