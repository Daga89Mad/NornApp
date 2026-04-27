// lib/views/menu_screen.dart
//
// Menu screen with four selectable styles (legacy, modern, ultra, threeD).
// - Toggle in AppBar cycles through the four styles.
// - Palette selector button shows current palette color and opens a menu to choose palettes.
// - Added "threeD" style: cards with depth, gradient, shadow and press animation.
// - Defensive layout to avoid unbounded constraints and small fixes for Material 3 text theme.
// - v2: Added Menú Semanal and Tareas Semanales after Calendario.

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:nornapp/views/calendar_screen.dart';
import 'package:nornapp/views/LoginBody.dart';
import 'package:nornapp/views/shifts_screen.dart';
import 'package:nornapp/views/friends_screen.dart';
import 'package:nornapp/views/qr_share_screen.dart';
import 'package:nornapp/views/diary_screen.dart';
import 'package:nornapp/views/weekly_menu_screen.dart';
import 'package:nornapp/views/weekly_tasks_screen.dart';
import 'dart:math' as math;
import '../core/settings_repository.dart';

enum MenuStyle { legacy, modern, ultra, threeD }

class MenuScreen extends StatefulWidget {
  const MenuScreen({Key? key}) : super(key: key);

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> {
  final TextEditingController _searchController = TextEditingController();
  MenuStyle _style = MenuStyle.modern;

  // Palette management
  final List<_Palette> _palettes = [
    const _Palette(
      name: 'Predeterminado',
      primary: Colors.indigo,
      background: Colors.white,
      text: Colors.black87,
    ),
    const _Palette(
      name: 'Rosado suave',
      primary: Color(0xFFD96DA6),
      background: Color(0xFFFFF6FB),
      text: Color(0xFF2B2B2B),
    ),
    const _Palette(
      name: 'Lavanda',
      primary: Color(0xFFB48BD9),
      background: Color(0xFFF7F2FB),
      text: Color(0xFF2B2B2B),
    ),
    const _Palette(
      name: 'Melocotón',
      primary: Color(0xFFFFB199),
      background: Color(0xFFFFFBF6),
      text: Color(0xFF2B2B2B),
    ),
    const _Palette(
      name: 'Verde menta',
      primary: Color(0xFF7ED9C6),
      background: Color(0xFFF6FFFB),
      text: Color(0xFF2B2B2B),
    ),
    const _Palette(
      name: 'Rojo',
      primary: Color(0xFFE53935),
      background: Color(0xFFFFF5F5),
      text: Color(0xFF2B2B2B),
    ),
    const _Palette(
      name: 'Azul claro',
      primary: Color(0xFF64B5F6),
      background: Color(0xFFF3FBFF),
      text: Color(0xFF1F2D3D),
    ),
    const _Palette(
      name: 'Amarillo',
      primary: Color(0xFFFFD54F),
      background: Color(0xFFFFFDF5),
      text: Color(0xFF2B2B2B),
    ),
  ];
  int _currentPaletteIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _searchController.addListener(() => setState(() {}));
  }

  Future<void> _loadSettings() async {
    final styleIdx = await SettingsRepository.instance.getMenuStyleIndex();
    final paletteIdx = await SettingsRepository.instance.getPaletteIndex();
    if (mounted) {
      setState(() {
        _style =
            MenuStyle.values[styleIdx.clamp(0, MenuStyle.values.length - 1)];
        _currentPaletteIndex = paletteIdx.clamp(0, _palettes.length - 1);
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _signOutAndGoToLogin(BuildContext context) async {
    await FirebaseAuth.instance.signOut();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginBody()),
      (route) => false,
    );
  }

  void _openCalendar() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const CalendarScreen()));
  }

  void _openWeeklyMenu() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const WeeklyMenuScreen()));
  }

  void _openWeeklyTasks() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const WeeklyTasksScreen()));
  }

  void _openShifts() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const ShiftsScreen()));
  }

  void _openFriends() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const FriendsScreen()));
  }

  void _openQrShare() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const QrShareScreen()));
  }

  void _openDiary() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const DiaryScreen()));
  }

  // Menu items — Menú semanal y Tareas semanales después de Calendario
  List<_MenuItemData> get _menuItems => [
    _MenuItemData(
      icon: Icons.calendar_today,
      label: 'Calendario',
      onTap: _openCalendar,
    ),
    _MenuItemData(
      icon: Icons.restaurant_menu,
      label: 'Menú semanal',
      onTap: _openWeeklyMenu,
    ),
    _MenuItemData(
      icon: Icons.checklist_rtl,
      label: 'Tareas semanales',
      onTap: _openWeeklyTasks,
    ),
    _MenuItemData(
      icon: Icons.work_history,
      label: 'Turnos',
      onTap: _openShifts,
    ),
    _MenuItemData(icon: Icons.group, label: 'Amigos', onTap: _openFriends),
    _MenuItemData(
      icon: Icons.menu_book_outlined,
      label: 'Diario',
      onTap: _openDiary,
    ),
    _MenuItemData(icon: Icons.group, label: 'Planilla de turnos', onTap: () {}),
    _MenuItemData(
      icon: Icons.qr_code,
      label: 'Compartir usuario (QR)',
      onTap: _openQrShare,
    ),
    _MenuItemData(icon: Icons.settings, label: 'Ajustes', onTap: () {}),
    _MenuItemData(
      icon: Icons.logout,
      label: 'Logout',
      onTap: () => _signOutAndGoToLogin(context),
    ),
  ];

  Color _colorForLabel(String label) {
    final palette = _palettes[_currentPaletteIndex];
    switch (label) {
      case 'Calendario':
        return palette.primary;
      case 'Menú semanal':
        return palette.primary.withOpacity(0.92);
      case 'Tareas semanales':
        return palette.primary.withOpacity(0.85);
      case 'Turnos':
        return palette.primary.withOpacity(0.95);
      case 'Amigos':
        return palette.primary.withOpacity(0.80);
      case 'Diario':
        return palette.primary.withOpacity(0.9);
      case 'Planilla de turnos':
        return palette.primary.withOpacity(0.75);
      case 'Compartir usuario (QR)':
        return palette.primary.withOpacity(0.88);
      case 'Ajustes':
        return palette.primary.withOpacity(0.70);
      case 'Logout':
        return Colors.redAccent;
      default:
        return palette.primary;
    }
  }

  void _cycleStyle() {
    final next = MenuStyle.values[(_style.index + 1) % MenuStyle.values.length];
    setState(() => _style = next);
    SettingsRepository.instance.saveMenuStyleIndex(next.index);
  }

  void _selectPalette(int index) {
    final clamped = index.clamp(0, _palettes.length - 1);
    setState(() => _currentPaletteIndex = clamped);
    SettingsRepository.instance.savePaletteIndex(clamped);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final media = MediaQuery.of(context);
    final crossAxis = media.size.width > 900
        ? 4
        : media.size.width > 600
        ? 3
        : 2;
    const spacing = 14.0;
    final palette = _palettes[_currentPaletteIndex];

    String styleLabel() {
      switch (_style) {
        case MenuStyle.legacy:
          return 'Legado';
        case MenuStyle.modern:
          return 'Moderno';
        case MenuStyle.ultra:
          return 'Ultra';
        case MenuStyle.threeD:
          return '3D';
      }
    }

    IconData styleIcon() {
      switch (_style) {
        case MenuStyle.legacy:
          return Icons.grid_view;
        case MenuStyle.modern:
          return Icons.view_comfy;
        case MenuStyle.ultra:
          return Icons.dashboard_customize;
        case MenuStyle.threeD:
          return Icons.threed_rotation;
      }
    }

    // Filtro de búsqueda
    final query = _searchController.text.trim().toLowerCase();
    final filtered = query.isEmpty
        ? _menuItems
        : _menuItems
              .where((m) => m.label.toLowerCase().contains(query))
              .toList();

    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: palette.background,
        automaticallyImplyLeading: false,
        title: Row(
          children: [
            Text(
              'Menú Principal',
              style: theme.textTheme.titleLarge?.copyWith(color: palette.text),
            ),
            const Spacer(),
            _PaletteButton(
              palette: palette,
              palettes: _palettes,
              currentIndex: _currentPaletteIndex,
              onSelected: _selectPalette,
            ),
            const SizedBox(width: 8),
            Text(
              styleLabel(),
              style: theme.textTheme.bodySmall?.copyWith(color: palette.text),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Cambiar estilo de menú',
              icon: Icon(styleIcon(), color: palette.text),
              onPressed: _cycleStyle,
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              const SizedBox(height: 8),
              _ProfileHeader(
                onEditProfile: () {},
                onQuickCalendar: _openCalendar,
                searchController: _searchController,
                palette: palette,
              ),
              const SizedBox(height: 12),
              _ModernSearchField(
                controller: _searchController,
                hint: 'Buscar opción…',
                palette: palette,
              ),
              const SizedBox(height: 16),
              Expanded(
                child: _buildGrid(filtered, crossAxis, spacing, palette, theme),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGrid(
    List<_MenuItemData> items,
    int crossAxis,
    double spacing,
    _Palette palette,
    ThemeData theme,
  ) {
    if (items.isEmpty) {
      return Center(
        child: Text(
          'Sin resultados',
          style: theme.textTheme.bodyMedium?.copyWith(color: palette.text),
        ),
      );
    }

    switch (_style) {
      case MenuStyle.legacy:
        return GridView.builder(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxis,
            crossAxisSpacing: spacing,
            mainAxisSpacing: spacing,
            childAspectRatio: 0.9,
          ),
          itemCount: items.length,
          itemBuilder: (_, i) {
            final item = items[i];
            final color = _colorForLabel(item.label);
            return _LegacyTile(
              icon: item.icon,
              label: item.label,
              color: color,
              onTap: item.onTap,
            );
          },
        );

      case MenuStyle.modern:
        return GridView.builder(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxis,
            crossAxisSpacing: spacing,
            mainAxisSpacing: spacing,
            childAspectRatio: 0.88,
          ),
          itemCount: items.length,
          itemBuilder: (_, i) {
            final item = items[i];
            final color = _colorForLabel(item.label);
            return _ModernTile(
              icon: item.icon,
              label: item.label,
              color: color,
              onTap: item.onTap,
            );
          },
        );

      case MenuStyle.ultra:
        return ListView.separated(
          itemCount: items.length,
          separatorBuilder: (_, __) => SizedBox(height: spacing),
          itemBuilder: (_, i) {
            final item = items[i];
            final color = _colorForLabel(item.label);
            return _UltraTile(
              icon: item.icon,
              label: item.label,
              color: color,
              onTap: item.onTap,
              palette: palette,
            );
          },
        );

      case MenuStyle.threeD:
        return GridView.builder(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxis,
            crossAxisSpacing: spacing,
            mainAxisSpacing: spacing,
            childAspectRatio: 0.88,
          ),
          itemCount: items.length,
          itemBuilder: (_, i) {
            final item = items[i];
            final color = _colorForLabel(item.label);
            return _ThreeDTile(
              icon: item.icon,
              label: item.label,
              color: color,
              onTap: item.onTap,
            );
          },
        );
    }
  }
}

// ════════════════════════════════════════════════════════════════════════════
// DATA MODEL
// ════════════════════════════════════════════════════════════════════════════

class _MenuItemData {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _MenuItemData({
    required this.icon,
    required this.label,
    required this.onTap,
  });
}

// ════════════════════════════════════════════════════════════════════════════
// PALETTE
// ════════════════════════════════════════════════════════════════════════════

class _Palette {
  final String name;
  final Color primary;
  final Color background;
  final Color text;

  const _Palette({
    required this.name,
    required this.primary,
    required this.background,
    required this.text,
  });
}

// ════════════════════════════════════════════════════════════════════════════
// TILES
// ════════════════════════════════════════════════════════════════════════════

class _LegacyTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _LegacyTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withOpacity(0.1),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 36),
              const SizedBox(height: 10),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: color,
                  fontSize: 13,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThreeDTile extends StatefulWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ThreeDTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    Key? key,
  }) : super(key: key);

  @override
  State<_ThreeDTile> createState() => _ThreeDTileState();
}

class _ThreeDTileState extends State<_ThreeDTile>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
      lowerBound: 0,
      upperBound: 1,
    );
    _scale = Tween<double>(begin: 1.0, end: 0.94).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _ctrl.forward(),
      onTapUp: (_) {
        _ctrl.reverse();
        widget.onTap();
      },
      onTapCancel: () => _ctrl.reverse(),
      child: AnimatedBuilder(
        animation: _scale,
        builder: (_, child) =>
            Transform.scale(scale: _scale.value, child: child),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                widget.color.withOpacity(0.95),
                widget.color.withOpacity(0.65),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: widget.color.withOpacity(0.38),
                blurRadius: 10,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(widget.icon, color: Colors.white, size: 36),
                const SizedBox(height: 10),
                Text(
                  widget.label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    fontSize: 13,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ModernTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ModernTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    const radius = 16.0;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(radius),
      elevation: 2,
      child: InkWell(
        borderRadius: BorderRadius.circular(radius),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14.0, horizontal: 10.0),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: const Color(0xFFF7E6F0)),
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.06),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [color.withOpacity(0.95), color.withOpacity(0.75)],
                  ),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: Colors.white, size: 22),
              ),
              const SizedBox(height: 10),
              Text(
                label,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF2B2B2B),
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Ultra-modern tile with large icon, subtitle and quick action button
class _UltraTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;
  final _Palette palette;

  const _UltraTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.subtitle = '',
    required this.palette,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final titleColor = palette.text;
    final subtitleColor = Colors.grey.shade700;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      elevation: 2,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 12.0),
          child: Row(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [color.withOpacity(0.95), color.withOpacity(0.75)],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: Colors.white, size: 32),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: titleColor,
                      ),
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: subtitleColor),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: onTap,
                icon: Icon(Icons.chevron_right, color: palette.text),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// PALETTE BUTTON
// ════════════════════════════════════════════════════════════════════════════

class _PaletteButton extends StatelessWidget {
  final _Palette palette;
  final List<_Palette> palettes;
  final int currentIndex;
  final void Function(int) onSelected;

  const _PaletteButton({
    required this.palette,
    required this.palettes,
    required this.currentIndex,
    required this.onSelected,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<int>(
      tooltip: 'Cambiar paleta',
      onSelected: onSelected,
      itemBuilder: (_) => List.generate(
        palettes.length,
        (i) => PopupMenuItem<int>(
          value: i,
          child: Row(
            children: [
              Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: palettes[i].primary,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                palettes[i].name,
                style: TextStyle(
                  fontWeight: i == currentIndex
                      ? FontWeight.bold
                      : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: palette.primary,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.grey.shade300, width: 1.5),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// PROFILE HEADER
// ════════════════════════════════════════════════════════════════════════════

class _ProfileHeader extends StatelessWidget {
  final VoidCallback onEditProfile;
  final VoidCallback onQuickCalendar;
  final TextEditingController searchController;
  final _Palette palette;

  const _ProfileHeader({
    required this.onEditProfile,
    required this.onQuickCalendar,
    required this.searchController,
    required this.palette,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final displayName = user?.displayName ?? 'Usuario';
    final email = user?.email ?? '';
    final textColor = palette.text;

    return Row(
      children: [
        Material(
          elevation: 2,
          shape: const CircleBorder(),
          child: CircleAvatar(
            radius: 28,
            backgroundColor: palette.primary.withOpacity(0.12),
            child: Text(
              displayName.isNotEmpty ? displayName[0].toUpperCase() : 'U',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 20,
                color: palette.primary,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                displayName,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: textColor,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                email,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: Colors.grey.shade700),
              ),
            ],
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Editar perfil',
              icon: Icon(Icons.edit, color: palette.text),
              onPressed: onEditProfile,
            ),
          ],
        ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// SEARCH FIELD
// ════════════════════════════════════════════════════════════════════════════

class _ModernSearchField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final _Palette palette;

  const _ModernSearchField({
    required this.controller,
    required this.hint,
    required this.palette,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    );
    final bg = palette.background == Colors.white
        ? Colors.grey.shade100
        : palette.background;

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: TextField(
        controller: controller,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: Icon(Icons.search, color: palette.text),
          suffixIcon: controller.text.isNotEmpty
              ? IconButton(
                  icon: Icon(Icons.clear, color: palette.text),
                  onPressed: () => controller.clear(),
                )
              : null,
          filled: true,
          fillColor: Colors.transparent,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
          border: border,
          enabledBorder: border,
          focusedBorder: border,
        ),
      ),
    );
  }
}
