// lib/views/menu_screen.dart
//
// Menu screen with four selectable styles (legacy, modern, ultra, threeD).
// - Toggle in AppBar cycles through the four styles.
// - Palette selector button shows current palette color and opens a menu to choose palettes.
// - Added "threeD" style: cards with depth, gradient, shadow and press animation.
// - Defensive layout to avoid unbounded constraints and small fixes for Material 3 text theme.

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:familycalendar/views/calendar_screen.dart';
import 'package:familycalendar/views/LoginBody.dart';
import 'package:familycalendar/views/shifts_screen.dart';
import 'package:familycalendar/views/friends_screen.dart';
import 'package:familycalendar/views/qr_share_screen.dart';
import 'package:familycalendar/views/diary_screen.dart';
import 'dart:math' as math;

enum MenuStyle { legacy, modern, ultra, threeD }

class MenuScreen extends StatefulWidget {
  const MenuScreen({Key? key}) : super(key: key);

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> {
  final TextEditingController _searchController = TextEditingController();
  MenuStyle _style = MenuStyle.modern;

  // Palette management: user can pick a palette; the palette affects accent colors used in cards/buttons.
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

  // Menu items (icons + labels). Colors will be overridden by palette mapping.
  List<_MenuItemData> get _menuItems => [
    _MenuItemData(
      icon: Icons.calendar_today,
      label: 'Calendario',
      onTap: _openCalendar,
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

  // Map to override menu item colors per palette (optional). If not present, use palette primary.
  Color _colorForLabel(String label) {
    final palette = _palettes[_currentPaletteIndex];
    switch (label) {
      case 'Calendario':
        return palette.primary;
      case 'Turnos':
        return palette.primary.withOpacity(0.95);
      case 'Amigos':
        return palette.primary.withOpacity(0.85);
      case 'Diario':
        return palette.primary.withOpacity(0.9);
      case 'Planilla de turnos':
        return palette.primary.withOpacity(0.8);
      case 'Compartir usuario (QR)':
        return palette.primary.withOpacity(0.9);
      case 'Ajustes':
        return palette.primary.withOpacity(0.75);
      case 'Logout':
        return Colors.redAccent;
      default:
        return palette.primary;
    }
  }

  void _cycleStyle() {
    setState(() {
      _style = MenuStyle.values[(_style.index + 1) % MenuStyle.values.length];
    });
  }

  void _selectPalette(int index) {
    setState(() {
      _currentPaletteIndex = index.clamp(0, _palettes.length - 1);
    });
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
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          child: Column(
            children: [
              _ProfileHeader(
                onEditProfile: () {
                  // placeholder
                },
                onQuickCalendar: _openCalendar,
                searchController: _searchController,
                palette: palette,
              ),
              const SizedBox(height: 16),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: _buildBodyForStyle(
                    _style,
                    crossAxis,
                    spacing,
                    palette,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'v1.0',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: palette.text,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      // placeholder
                    },
                    icon: Icon(
                      Icons.help_outline,
                      size: 18,
                      color: palette.text,
                    ),
                    label: Text('Ayuda', style: TextStyle(color: palette.text)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBodyForStyle(
    MenuStyle style,
    int crossAxis,
    double spacing,
    _Palette palette,
  ) {
    switch (style) {
      case MenuStyle.legacy:
        return _legacyGrid(crossAxis, spacing, palette);
      case MenuStyle.modern:
        return _modernGrid(crossAxis, spacing, palette);
      case MenuStyle.ultra:
        return _ultraList(palette);
      case MenuStyle.threeD:
        return _threeDGrid(crossAxis, spacing, palette);
    }
  }

  Widget _legacyGrid(int crossAxis, double spacing, _Palette palette) {
    return GridView.count(
      key: const ValueKey('legacy'),
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.zero,
      crossAxisCount: crossAxis,
      crossAxisSpacing: spacing,
      mainAxisSpacing: spacing,
      childAspectRatio: 1.1,
      children: _menuItems.map((item) {
        return _LegacyMenuButton(
          icon: item.icon,
          label: item.label,
          onTap: item.onTap,
          palette: palette,
          colorOverride: _colorForLabel(item.label),
        );
      }).toList(),
    );
  }

  Widget _modernGrid(int crossAxis, double spacing, _Palette palette) {
    return GridView.builder(
      key: const ValueKey('modern'),
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.zero,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxis,
        crossAxisSpacing: spacing,
        mainAxisSpacing: spacing,
        childAspectRatio: 1.05,
      ),
      itemCount: _menuItems.length,
      itemBuilder: (context, index) {
        final item = _menuItems[index];
        return _ModernCardButLegacyButtonStyle(
          icon: item.icon,
          label: item.label,
          color: _colorForLabel(item.label),
          onTap: item.onTap,
          palette: palette,
        );
      },
    );
  }

  Widget _ultraList(_Palette palette) {
    return ListView.separated(
      key: const ValueKey('ultra'),
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.zero,
      itemCount: _menuItems.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final item = _menuItems[index];
        return _UltraTile(
          icon: item.icon,
          label: item.label,
          color: _colorForLabel(item.label),
          onTap: item.onTap,
          subtitle: _subtitleForLabel(item.label),
          palette: palette,
        );
      },
    );
  }

  // New 3D grid: uses _ThreeDCard for each item
  Widget _threeDGrid(int crossAxis, double spacing, _Palette palette) {
    return GridView.builder(
      key: const ValueKey('threeD'),
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.zero,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxis,
        crossAxisSpacing: spacing,
        mainAxisSpacing: spacing,
        childAspectRatio: 1.02,
      ),
      itemCount: _menuItems.length,
      itemBuilder: (context, index) {
        final item = _menuItems[index];
        return _ThreeDCard(
          icon: item.icon,
          label: item.label,
          color: _colorForLabel(item.label),
          onTap: item.onTap,
          palette: palette,
        );
      },
    );
  }

  String _subtitleForLabel(String label) {
    switch (label) {
      case 'Calendario':
        return 'Ver y gestionar eventos';
      case 'Turnos':
        return 'Organiza y asigna turnos';
      case 'Amigos':
        return 'Contactos y compartir';
      case 'Diario':
        return 'Escribe tus pensamientos y eventos diarios';
      case 'Diario':
        return 'Escribe tus pensamientos del día';
      case 'Planilla de turnos':
        return 'Organiza turnos de forma colaborativa';
      case 'Compartir usuario (QR)':
        return 'Comparte tu perfil con QR';
      case 'Ajustes':
        return 'Preferencias de la aplicación';
      case 'Logout':
        return 'Cerrar sesión segura';
      default:
        return '';
    }
  }
}

/// Palette model
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

/// Data model for menu items
class _MenuItemData {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  _MenuItemData({required this.icon, required this.label, required this.onTap});
}

/// Palette selector button (shows current color and opens menu)
class _PaletteButton extends StatelessWidget {
  final _Palette palette;
  final List<_Palette> palettes;
  final int currentIndex;
  final ValueChanged<int> onSelected;

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
      tooltip: 'Paleta de colores',
      onSelected: onSelected,
      itemBuilder: (context) {
        return List.generate(palettes.length, (i) {
          final p = palettes[i];
          return PopupMenuItem<int>(
            value: i,
            child: Row(
              children: [
                Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: p.primary,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(p.name, overflow: TextOverflow.ellipsis)),
                if (i == currentIndex) const Icon(Icons.check, size: 18),
              ],
            ),
          );
        });
      },
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: palette.primary,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: palette.primary.withOpacity(0.18),
              blurRadius: 6,
              offset: const Offset(0, 3),
            ),
          ],
        ),
      ),
    );
  }
}

/// Legacy button style (compact square buttons)
class _LegacyMenuButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final _Palette palette;
  final Color colorOverride;

  const _LegacyMenuButton({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.palette,
    required this.colorOverride,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final bg = palette.background;
    final iconColor = colorOverride;
    final textColor = palette.text;

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(10),
      elevation: 2,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 8.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 32, color: iconColor),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: textColor,
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

/// Modern card that visually matches the legacy button's icon/label sizing
class _ModernCardButLegacyButtonStyle extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final _Palette palette;

  const _ModernCardButLegacyButtonStyle({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    required this.palette,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final radius = 12.0;
    final labelColor = palette.text;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(radius),
      elevation: 2,
      child: InkWell(
        borderRadius: BorderRadius.circular(radius),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 8.0),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: Colors.grey.shade100),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [color.withOpacity(0.95), color.withOpacity(0.75)],
                  ),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: Colors.white, size: 20),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: labelColor,
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

/// 3D card widget: tilt + depth + press animation
class _ThreeDCard extends StatefulWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final _Palette palette;

  const _ThreeDCard({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    required this.palette,
    Key? key,
  }) : super(key: key);

  @override
  State<_ThreeDCard> createState() => _ThreeDCardState();
}

class _ThreeDCardState extends State<_ThreeDCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _pressAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 160),
    );
    _pressAnim = Tween<double>(
      begin: 0.0,
      end: 0.06,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails d) => _ctrl.forward();
  void _onTapUp(TapUpDetails d) {
    _ctrl.reverse();
    widget.onTap();
  }

  void _onTapCancel() => _ctrl.reverse();

  @override
  Widget build(BuildContext context) {
    final radius = 16.0;
    final baseColor = widget.color;
    final palette = widget.palette;

    return AnimatedBuilder(
      animation: _pressAnim,
      builder: (context, child) {
        final tilt = _pressAnim.value; // 0..0.06
        final matrix = Matrix4.identity()
          ..setEntry(3, 2, 0.001) // perspective
          ..rotateX(-tilt)
          ..rotateY(tilt / 2);
        final elevation = 18.0 * (1 - tilt);
        return Transform(
          transform: matrix,
          alignment: Alignment.center,
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(radius),
            elevation: elevation,
            shadowColor: baseColor.withOpacity(0.28),
            child: InkWell(
              borderRadius: BorderRadius.circular(radius),
              onTapDown: _onTapDown,
              onTapUp: _onTapUp,
              onTapCancel: _onTapCancel,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 14.0,
                  horizontal: 12.0,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(radius),
                  gradient: LinearGradient(
                    begin: Alignment(-0.8, -0.6),
                    end: Alignment(0.8, 0.6),
                    colors: [
                      baseColor.withOpacity(0.98),
                      baseColor.withOpacity(0.78),
                    ],
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Icon circle with subtle inner shadow effect (simulated)
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withOpacity(0.12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.12),
                            blurRadius: 6,
                            offset: const Offset(0, 4),
                          ),
                          BoxShadow(
                            color: Colors.white.withOpacity(0.06),
                            blurRadius: 2,
                            offset: const Offset(-2, -2),
                          ),
                        ],
                      ),
                      child: Icon(widget.icon, color: Colors.white, size: 30),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      widget.label,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: palette.text,
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
      },
    );
  }
}

/// Rosado-specific card (kept for palette variants; uses palette colors)
class _RosadoCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _RosadoCard({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final radius = 14.0;
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

/// Profile header with constrained actions to avoid layout issues
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

/// Simple search field used in the header area
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
