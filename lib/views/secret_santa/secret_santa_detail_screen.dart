// lib/views/secret_santa/secret_santa_detail_screen.dart
//
// Detalle de un AMIGO INVISIBLE:
//  · Cabecera con límite de gasto, fecha y estado.
//  · Tras el sorteo: tarjeta "Te toca regalar a…" (oculta hasta que la tocas)
//    con la lista de deseos de esa persona.
//  · Mi lista de deseos (opcional, editable siempre).
//  · Jugadores: apuntados e invitados pendientes.
//  · Apuntarme / salir, y para el organizador: editar, sortear y borrar.

import 'package:flutter/material.dart';
import '../../core/secret_santa_repository.dart';
import '../../models/secret_santa_models.dart';
import 'secret_santa_form_screen.dart';
import 'secret_santa_widgets.dart';

class SecretSantaDetailScreen extends StatefulWidget {
  final String gameId;
  final SecretSantaGame? initial;

  const SecretSantaDetailScreen({
    super.key,
    required this.gameId,
    this.initial,
  });

  @override
  State<SecretSantaDetailScreen> createState() =>
      _SecretSantaDetailScreenState();
}

class _SecretSantaDetailScreenState extends State<SecretSantaDetailScreen> {
  final _repo = SecretSantaRepository.instance;
  late final Stream<SecretSantaGame?> _gameStream = _repo.watchGame(
    widget.gameId,
  );
  late final Stream<Map<String, SecretSantaWishlist>> _wishStream = _repo
      .watchWishlists(widget.gameId);
  late final Stream<SecretSantaAssignment?> _assignStream = _repo
      .watchMyAssignment(widget.gameId);
  late SantaPeople _people = SantaPeople(myUid: _repo.uid);

  bool _revealed = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    SantaPeople.load(_repo.uid).then((p) {
      if (mounted) setState(() => _people = p);
    });
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _run(Future<void> Function() action, {String? ok}) async {
    setState(() => _busy = true);
    try {
      await action();
      if (ok != null) _snack(ok);
    } catch (e) {
      _snack('No se pudo completar: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm(String title, String body, String action) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: SantaColors.primary),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(action),
          ),
        ],
      ),
    );
    return r == true;
  }

  Future<void> _draw(SecretSantaGame g) async {
    final ok = await _confirm(
      '¿Hacer el sorteo?',
      'Se sorteará entre los ${g.participants.length} jugadores apuntados. '
          'Nadie, ni siquiera tú como organizador, podrá ver a quién le ha '
          'tocado cada uno. Después ya no se podrá apuntar más gente.',
      'Sortear',
    );
    if (ok) await _run(() => _repo.requestDraw(g.id));
  }

  Future<void> _delete(SecretSantaGame g) async {
    final ok = await _confirm(
      '¿Borrar el sorteo?',
      'Se borrará «${g.name}» para todos los jugadores, con sus listas de '
          'deseos.',
      'Borrar',
    );
    if (!ok) return;
    await _run(() => _repo.deleteGame(g.id));
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _edit(SecretSantaGame g) async {
    await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => SecretSantaFormScreen(game: g)),
    );
  }

  Future<void> _editWishlist(SecretSantaWishlist? current) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _WishlistSheet(gameId: widget.gameId, initial: current),
    );
    if (saved == true) _snack('Lista de deseos guardada');
  }

  // ══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<SecretSantaGame?>(
      stream: _gameStream,
      initialData: widget.initial,
      builder: (context, snap) {
        final g = snap.data;
        if (g == null) {
          return Scaffold(
            backgroundColor: SantaColors.background,
            appBar: AppBar(
              backgroundColor: SantaColors.primary,
              foregroundColor: Colors.white,
            ),
            body: snap.connectionState == ConnectionState.waiting
                ? const Center(child: CircularProgressIndicator())
                : const SantaEmptyState(
                    icon: Icons.card_giftcard_rounded,
                    title: 'Este sorteo ya no existe',
                  ),
          );
        }
        final myUid = _repo.uid;
        final isOwner = g.isOwner(myUid);
        final joined = g.hasJoined(myUid);

        return Scaffold(
          backgroundColor: SantaColors.background,
          bottomNavigationBar: _buildBottomBar(g, isOwner, joined),
          body: StreamBuilder<Map<String, SecretSantaWishlist>>(
            stream: _wishStream,
            builder: (context, wsnap) {
              final wishes = wsnap.data ?? const {};
              return CustomScrollView(
                slivers: [
                  _buildAppBar(g, isOwner),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                    sliver: SliverList.list(
                      children: [
                        if (g.drawError.isNotEmpty &&
                            g.status == SecretSantaStatus.open) ...[
                          _errorBanner(g.drawError),
                          const SizedBox(height: 14),
                        ],
                        if (g.status == SecretSantaStatus.drawing) ...[
                          _drawingCard(),
                          const SizedBox(height: 14),
                        ],
                        if (g.status == SecretSantaStatus.drawn && joined) ...[
                          _assignmentCard(g, wishes),
                          const SizedBox(height: 14),
                        ],
                        if (joined) ...[
                          _myWishlistCard(wishes[myUid]),
                          const SizedBox(height: 14),
                        ] else if (g.status == SecretSantaStatus.open) ...[
                          _inviteCard(),
                          const SizedBox(height: 14),
                        ],
                        if (g.notes.isNotEmpty) ...[
                          _notesCard(g.notes),
                          const SizedBox(height: 14),
                        ],
                        _playersCard(g, wishes),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildAppBar(SecretSantaGame g, bool isOwner) {
    final canEdit = isOwner && g.status == SecretSantaStatus.open;
    return SliverAppBar(
      pinned: true,
      expandedHeight: 200,
      backgroundColor: SantaColors.primary,
      foregroundColor: Colors.white,
      title: Text(g.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      actions: [
        if (canEdit)
          IconButton(
            tooltip: 'Editar',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => _edit(g),
          ),
        if (isOwner)
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'delete') _delete(g);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'delete',
                child: ListTile(
                  leading: Icon(Icons.delete_outline, color: Colors.red),
                  title: Text('Borrar sorteo'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        collapseMode: CollapseMode.pin,
        background: Container(
          decoration: const BoxDecoration(gradient: SantaColors.header),
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          alignment: Alignment.bottomLeft,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Límite de gasto',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              Text(
                fmtBudget(g.budgetCents),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  SantaStatusChip(status: g.status, onDark: true),
                  if (g.eventDate != null)
                    SantaChip(
                      icon: Icons.event_outlined,
                      label: fmtSantaDate(g.eventDate!),
                      onDark: true,
                    ),
                  SantaChip(
                    icon: Icons.person_outline,
                    label: isOwner
                        ? 'Organizas tú'
                        : 'Organiza ${_people.name(g.ownerId, game: g)}',
                    onDark: true,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget? _buildBottomBar(SecretSantaGame g, bool isOwner, bool joined) {
    if (g.status != SecretSantaStatus.open) return null;
    final buttons = <Widget>[];

    if (!joined) {
      buttons.add(
        Expanded(
          child: FilledButton.icon(
            style: _btnStyle(SantaColors.green),
            onPressed: _busy
                ? null
                : () => _run(() => _repo.join(g.id), ok: '¡Te has apuntado!'),
            icon: const Icon(Icons.how_to_reg),
            label: const Text('Apuntarme'),
          ),
        ),
      );
    } else if (!isOwner) {
      buttons.add(
        Expanded(
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: SantaColors.primary,
              minimumSize: const Size.fromHeight(52),
              side: const BorderSide(color: SantaColors.primary),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            onPressed: _busy ? null : () => _run(() => _repo.leave(g.id)),
            icon: const Icon(Icons.logout),
            label: const Text('Salir del sorteo'),
          ),
        ),
      );
    }

    if (isOwner) {
      if (buttons.isNotEmpty) buttons.add(const SizedBox(width: 10));
      buttons.add(
        Expanded(
          child: FilledButton.icon(
            style: _btnStyle(SantaColors.primary),
            onPressed: _busy || !g.canDraw ? null : () => _draw(g),
            icon: const Icon(Icons.casino_outlined),
            label: Text(
              g.canDraw
                  ? 'Sortear'
                  : 'Faltan ${SecretSantaGame.minPlayers - g.participants.length}',
            ),
          ),
        ),
      );
    }

    if (buttons.isEmpty) return null;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Row(children: buttons),
      ),
    );
  }

  ButtonStyle _btnStyle(Color c) => FilledButton.styleFrom(
    backgroundColor: c,
    minimumSize: const Size.fromHeight(52),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
  );

  // ── Tarjetas ──────────────────────────────────────────────────────────────

  Widget _errorBanner(String msg) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.orange.shade50,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      children: [
        Icon(Icons.warning_amber_rounded, color: Colors.orange.shade800),
        const SizedBox(width: 10),
        Expanded(child: Text(msg)),
      ],
    ),
  );

  Widget _drawingCard() => const SantaCard(
    child: Row(
      children: [
        SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 3),
        ),
        SizedBox(width: 16),
        Expanded(
          child: Text(
            'Haciendo el sorteo en secreto… En unos segundos cada jugador '
            'verá a quién le toca regalar.',
          ),
        ),
      ],
    ),
  );

  Widget _assignmentCard(
    SecretSantaGame g,
    Map<String, SecretSantaWishlist> wishes,
  ) {
    return StreamBuilder<SecretSantaAssignment?>(
      stream: _assignStream,
      builder: (context, snap) {
        final a = snap.data;
        if (a == null) return _drawingCard();
        final name = a.receiverUid.isEmpty
            ? a.receiverName
            : _people.name(a.receiverUid, game: g, me: false);
        final wish = wishes[a.receiverUid];

        return GestureDetector(
          onTap: () => setState(() => _revealed = !_revealed),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: _revealed
                  ? const LinearGradient(
                      colors: [Color(0xFF1B5E20), Color(0xFF43A047)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : SantaColors.header,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: SantaColors.primary.withOpacity(0.25),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: !_revealed
                  ? const Column(
                      key: ValueKey('hidden'),
                      children: [
                        Text('🎁', style: TextStyle(fontSize: 52)),
                        SizedBox(height: 8),
                        Text(
                          'Toca para descubrir a quién te toca regalar',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Que nadie mire tu pantalla 🤫',
                          style: TextStyle(color: Colors.white70),
                        ),
                      ],
                    )
                  : Column(
                      key: const ValueKey('shown'),
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Te toca regalar a',
                          style: TextStyle(color: Colors.white70),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            SantaAvatar(
                              uid: a.receiverUid,
                              people: _people,
                              game: g,
                              size: 48,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                name,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 26,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            const Icon(
                              Icons.visibility_off_outlined,
                              color: Colors.white70,
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: _wishlistBody(
                            wish,
                            onDark: true,
                            emptyText:
                                'Todavía no ha escrito su lista de deseos.',
                          ),
                        ),
                        if (g.budgetCents > 0) ...[
                          const SizedBox(height: 10),
                          Text(
                            'Máximo ${fmtBudget(g.budgetCents)}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
            ),
          ),
        );
      },
    );
  }

  Widget _wishlistBody(
    SecretSantaWishlist? w, {
    bool onDark = false,
    required String emptyText,
  }) {
    final fg = onDark ? Colors.white : Colors.black87;
    final sub = onDark ? Colors.white70 : Colors.grey.shade600;
    if (w == null || w.isEmpty) {
      return Text(emptyText, style: TextStyle(color: sub));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Lista de deseos',
          style: TextStyle(color: sub, fontSize: 12),
        ),
        const SizedBox(height: 6),
        for (final item in w.items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.star_rounded, size: 18, color: SantaColors.gold),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(item, style: TextStyle(color: fg)),
                ),
              ],
            ),
          ),
        if (w.note.trim().isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            w.note,
            style: TextStyle(color: sub, fontStyle: FontStyle.italic),
          ),
        ],
      ],
    );
  }

  Widget _myWishlistCard(SecretSantaWishlist? w) => SantaCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.favorite_border, color: SantaColors.primary),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Mi lista de deseos',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
            TextButton.icon(
              onPressed: () => _editWishlist(w),
              icon: Icon(w == null || w.isEmpty ? Icons.add : Icons.edit),
              label: Text(w == null || w.isEmpty ? 'Añadir' : 'Editar'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        _wishlistBody(
          w,
          emptyText:
              'Opcional: apunta ideas para que tu amigo invisible acierte.',
        ),
      ],
    ),
  );

  Widget _inviteCard() => SantaCard(
    child: Row(
      children: [
        const Text('✉️', style: TextStyle(fontSize: 32)),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            'Te han invitado a este amigo invisible. Apúntate para entrar en '
            'el sorteo y poder escribir tu lista de deseos.',
            style: TextStyle(color: Colors.grey.shade800),
          ),
        ),
      ],
    ),
  );

  Widget _notesCard(String notes) => SantaCard(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.notes_outlined, color: Colors.grey.shade600),
        const SizedBox(width: 10),
        Expanded(child: Text(notes)),
      ],
    ),
  );

  Widget _playersCard(
    SecretSantaGame g,
    Map<String, SecretSantaWishlist> wishes,
  ) {
    final joined = [...g.participants];
    final pending = g.invited.where((u) => !joined.contains(u)).toList();

    Widget tile(String uid, bool isIn) {
      final hasWish = !(wishes[uid]?.isEmpty ?? true);
      return ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        leading: SantaAvatar(uid: uid, people: _people, game: g, size: 38),
        title: Text(_people.name(uid, game: g)),
        subtitle: Text(
          isIn
              ? (hasWish ? 'Apuntado · con lista de deseos' : 'Apuntado')
              : 'Invitado · sin responder',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
        trailing: Icon(
          isIn ? Icons.check_circle : Icons.schedule,
          color: isIn ? SantaColors.green : Colors.grey.shade400,
        ),
      );
    }

    return SantaCard(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text(
              'Jugadores (${joined.length})',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
          if (joined.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Nadie se ha apuntado todavía.',
                style: TextStyle(color: Colors.grey.shade600),
              ),
            ),
          for (final u in joined) tile(u, true),
          if (pending.isNotEmpty && g.status == SecretSantaStatus.open) ...[
            const Divider(height: 20),
            for (final u in pending) tile(u, false),
          ],
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// EDITOR DE LA LISTA DE DESEOS
// ════════════════════════════════════════════════════════════════════════════

class _WishlistSheet extends StatefulWidget {
  final String gameId;
  final SecretSantaWishlist? initial;
  const _WishlistSheet({required this.gameId, this.initial});

  @override
  State<_WishlistSheet> createState() => _WishlistSheetState();
}

class _WishlistSheetState extends State<_WishlistSheet> {
  late final List<String> _items = [...?widget.initial?.items];
  late final TextEditingController _note = TextEditingController(
    text: widget.initial?.note ?? '',
  );
  final _newItem = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _note.dispose();
    _newItem.dispose();
    super.dispose();
  }

  void _add() {
    final t = _newItem.text.trim();
    if (t.isEmpty) return;
    setState(() {
      _items.add(t);
      _newItem.clear();
    });
  }

  Future<void> _save() async {
    _add();
    setState(() => _saving = true);
    try {
      await SecretSantaRepository.instance.saveWishlist(
        widget.gameId,
        _items,
        _note.text,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo guardar: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        decoration: const BoxDecoration(
          color: SantaColors.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 14, 20, 4),
                child: Row(
                  children: [
                    Text('🎄', style: TextStyle(fontSize: 22)),
                    SizedBox(width: 8),
                    Text(
                      'Mi lista de deseos',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  children: [
                    for (var i = 0; i < _items.length; i++)
                      Card(
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: ListTile(
                          leading: const Icon(
                            Icons.star_rounded,
                            color: SantaColors.gold,
                          ),
                          title: Text(_items[i]),
                          trailing: IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () =>
                                setState(() => _items.removeAt(i)),
                          ),
                        ),
                      ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _newItem,
                      textCapitalization: TextCapitalization.sentences,
                      onSubmitted: (_) => _add(),
                      decoration: InputDecoration(
                        hintText: 'Añadir un deseo (libro, talla, color…)',
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                        suffixIcon: IconButton(
                          icon: const Icon(
                            Icons.add_circle,
                            color: SantaColors.primary,
                          ),
                          onPressed: _add,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _note,
                      minLines: 1,
                      maxLines: 3,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: 'Nota (opcional): "nada de ropa", tallas…',
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: SantaColors.primary,
                    minimumSize: const Size.fromHeight(50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: _saving ? null : _save,
                  icon: const Icon(Icons.check),
                  label: const Text('Guardar'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
