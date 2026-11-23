// lib/views/secret_santa/secret_santa_screen.dart
//
// AMIGO INVISIBLE: listado de los juegos en los que estoy invitado
// (abiertos primero, luego sorteados). Desde aquí se crea uno nuevo.

import 'package:flutter/material.dart';
import '../../core/secret_santa_repository.dart';
import '../../models/secret_santa_models.dart';
import 'secret_santa_detail_screen.dart';
import 'secret_santa_form_screen.dart';
import 'secret_santa_widgets.dart';

class SecretSantaScreen extends StatefulWidget {
  const SecretSantaScreen({super.key});

  @override
  State<SecretSantaScreen> createState() => _SecretSantaScreenState();
}

class _SecretSantaScreenState extends State<SecretSantaScreen> {
  final _repo = SecretSantaRepository.instance;
  late final Stream<List<SecretSantaGame>> _stream = _repo.watchGames();
  late SantaPeople _people = SantaPeople(myUid: _repo.uid);

  @override
  void initState() {
    super.initState();
    SantaPeople.load(_repo.uid).then((p) {
      if (mounted) setState(() => _people = p);
    });
  }

  Future<void> _openCreate() async {
    final id = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const SecretSantaFormScreen()),
    );
    if (id == null || !mounted) return;
    _openDetail(id);
  }

  void _openDetail(String id, [SecretSantaGame? initial]) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SecretSantaDetailScreen(gameId: id, initial: initial),
      ),
    );
  }

  List<SecretSantaGame> _sorted(List<SecretSantaGame> all) {
    final list = [...all];
    list.sort((a, b) {
      final ao = a.status == SecretSantaStatus.drawn ? 1 : 0;
      final bo = b.status == SecretSantaStatus.drawn ? 1 : 0;
      if (ao != bo) return ao - bo;
      final ad = a.eventDate ?? a.createdAt ?? DateTime(2100);
      final bd = b.eventDate ?? b.createdAt ?? DateTime(2100);
      return ad.compareTo(bd);
    });
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SantaColors.background,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: SantaColors.primary,
        foregroundColor: Colors.white,
        onPressed: _openCreate,
        icon: const Icon(Icons.add),
        label: const Text('Nuevo sorteo'),
      ),
      body: StreamBuilder<List<SecretSantaGame>>(
        stream: _stream,
        builder: (context, snap) {
          final loading =
              snap.connectionState == ConnectionState.waiting && !snap.hasData;
          final games = _sorted(snap.data ?? const []);
          final pending = games
              .where(
                (g) =>
                    g.status == SecretSantaStatus.open &&
                    !g.hasJoined(_repo.uid),
              )
              .length;

          return CustomScrollView(
            slivers: [
              _buildAppBar(games.length, pending),
              if (snap.hasError)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: SantaEmptyState(
                    icon: Icons.cloud_off,
                    title: 'No se pudieron cargar los sorteos',
                    subtitle: '${snap.error}',
                  ),
                )
              else if (loading)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (games.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: SantaEmptyState(
                    icon: Icons.card_giftcard_rounded,
                    title: 'Todavía no hay ningún amigo invisible',
                    subtitle:
                        'Crea uno, invita a tus amigos, fija el límite de '
                        'gasto y deja que la app haga el sorteo en secreto.',
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  sliver: SliverList.separated(
                    itemCount: games.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (_, i) => _GameTile(
                      game: games[i],
                      people: _people,
                      myUid: _repo.uid,
                      onTap: () => _openDetail(games[i].id, games[i]),
                    ),
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 110)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildAppBar(int total, int pending) {
    return SliverAppBar(
      pinned: true,
      expandedHeight: 170,
      backgroundColor: SantaColors.primary,
      foregroundColor: Colors.white,
      title: const Text('Amigo invisible'),
      flexibleSpace: FlexibleSpaceBar(
        collapseMode: CollapseMode.pin,
        background: Container(
          decoration: const BoxDecoration(gradient: SantaColors.header),
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          alignment: Alignment.bottomLeft,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      total == 1 ? '1 sorteo' : '$total sorteos',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      pending > 0
                          ? (pending == 1
                                ? 'Te espera 1 invitación'
                                : 'Te esperan $pending invitaciones')
                          : 'Nadie sabe a quién le ha tocado 🤫',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),
              const Text('🎁', style: TextStyle(fontSize: 54)),
            ],
          ),
        ),
      ),
    );
  }
}

class _GameTile extends StatelessWidget {
  final SecretSantaGame game;
  final SantaPeople people;
  final String myUid;
  final VoidCallback onTap;

  const _GameTile({
    required this.game,
    required this.people,
    required this.myUid,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final invitedOnly =
        game.status == SecretSantaStatus.open && !game.hasJoined(myUid);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: SantaCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: SantaColors.header,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.card_giftcard_rounded,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          game.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          game.isOwner(myUid)
                              ? 'Lo organizas tú'
                              : 'Organiza ${people.name(game.ownerId, game: game)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SantaStatusChip(status: game.status),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  SantaChip(
                    icon: Icons.euro_rounded,
                    label: fmtBudget(game.budgetCents),
                    color: SantaColors.green,
                  ),
                  if (game.eventDate != null)
                    SantaChip(
                      icon: Icons.event_outlined,
                      label: fmtSantaDate(game.eventDate!),
                    ),
                  SantaChip(
                    icon: Icons.people_alt_outlined,
                    label:
                        '${game.participants.length}/${game.invited.length} apuntados',
                    color: Colors.blueGrey,
                  ),
                ],
              ),
              if (invitedOnly) ...[
                const SizedBox(height: 10),
                Text(
                  '¡Te han invitado! Entra para apuntarte.',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: SantaColors.primary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
