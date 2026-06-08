// lib/core/settings_repository.dart
//
// Persiste preferencias de UI con SharedPreferences.

import 'package:shared_preferences/shared_preferences.dart';

class SettingsRepository {
  SettingsRepository._();
  static final SettingsRepository instance = SettingsRepository._();

  // ── Claves ────────────────────────────────────────────────────────────────
  static const _kMenuStyle = 'menu_style';
  static const _kPaletteIndex = 'menu_palette';

  static const _kCalFilterTurnos = 'cal_filter_turnos';
  static const _kCalHiddenCategories =
      'cal_hidden_categories'; // ← NUEVO (stringList)
  static const _kCalCompact = 'cal_compact_mode';
  static const _kCalBgName = 'cal_bg_name';
  static const _kCalDesign = 'cal_design';

  // ── Menu ─────────────────────────────────────────────────────────────────

  Future<int> getMenuStyleIndex() async {
    final p = await SharedPreferences.getInstance();
    return p.getInt(_kMenuStyle) ?? 1;
  }

  Future<void> saveMenuStyleIndex(int index) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kMenuStyle, index);
  }

  Future<int> getPaletteIndex() async {
    final p = await SharedPreferences.getInstance();
    return p.getInt(_kPaletteIndex) ?? 0;
  }

  Future<void> savePaletteIndex(int index) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kPaletteIndex, index);
  }

  // ── Calendar ─────────────────────────────────────────────────────────────

  Future<CalendarSettings> getCalendarSettings() async {
    final p = await SharedPreferences.getInstance();
    return CalendarSettings(
      filterTurnos: p.getBool(_kCalFilterTurnos) ?? true,
      compactMode: p.getBool(_kCalCompact) ?? false,
      bgName: p.getString(_kCalBgName) ?? 'Blanco',
      design: p.getString(_kCalDesign) ?? 'Predeterminado',
    );
  }

  Future<void> saveCalendarSettings(CalendarSettings s) async {
    final p = await SharedPreferences.getInstance();
    await Future.wait([
      p.setBool(_kCalFilterTurnos, s.filterTurnos),
      p.setBool(_kCalCompact, s.compactMode),
      p.setString(_kCalBgName, s.bgName),
      p.setString(_kCalDesign, s.design),
    ]);
  }

  // ── Categorías ocultas (filtro dinámico) ───────────────────────────────────

  Future<List<String>> getHiddenCategoryKeys() async {
    final p = await SharedPreferences.getInstance();
    return p.getStringList(_kCalHiddenCategories) ?? const [];
  }

  Future<void> saveHiddenCategoryKeys(List<String> keys) async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_kCalHiddenCategories, keys);
  }
}

/// Preferencias del calendario (sin las categorías, que ahora son dinámicas).
class CalendarSettings {
  final bool filterTurnos;
  final bool compactMode;
  final String bgName;
  final String design;

  const CalendarSettings({
    required this.filterTurnos,
    required this.compactMode,
    required this.bgName,
    required this.design,
  });
}
