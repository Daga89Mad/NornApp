// lib/core/settings_repository.dart
//
// Persiste preferencias de UI con SharedPreferences.
// Es el único sitio donde se leen/escriben estas claves.

import 'package:shared_preferences/shared_preferences.dart';

class SettingsRepository {
  SettingsRepository._();
  static final SettingsRepository instance = SettingsRepository._();

  // ── Claves ────────────────────────────────────────────────────────────────
  static const _kMenuStyle = 'menu_style'; // int (índice enum)
  static const _kPaletteIndex = 'menu_palette'; // int

  static const _kCalFilterWork = 'cal_filter_trabajo';
  static const _kCalFilterEvents = 'cal_filter_eventos';
  static const _kCalFilterCitas = 'cal_filter_citas';
  static const _kCalFilterRemind = 'cal_filter_recordatorios';
  static const _kCalFilterBebe = 'cal_filter_bebe';
  static const _kCalFilterPeriod = 'cal_filter_periodo';
  static const _kCalCompact = 'cal_compact_mode';
  static const _kCalBgName = 'cal_bg_name';
  static const _kCalDesign = 'cal_design';

  // ── Menu ─────────────────────────────────────────────────────────────────

  Future<int> getMenuStyleIndex() async {
    final p = await SharedPreferences.getInstance();
    return p.getInt(_kMenuStyle) ?? 1; // default: modern (index 1)
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
      filterTrabajo: p.getBool(_kCalFilterWork) ?? true,
      filterEventos: p.getBool(_kCalFilterEvents) ?? true,
      filterCitas: p.getBool(_kCalFilterCitas) ?? true,
      filterRecordatorios: p.getBool(_kCalFilterRemind) ?? true,
      filterBebe: p.getBool(_kCalFilterBebe) ?? true,
      filterPeriodo: p.getBool(_kCalFilterPeriod) ?? true,
      compactMode: p.getBool(_kCalCompact) ?? false,
      bgName: p.getString(_kCalBgName) ?? 'Blanco',
      design: p.getString(_kCalDesign) ?? 'Predeterminado',
    );
  }

  Future<void> saveCalendarSettings(CalendarSettings s) async {
    final p = await SharedPreferences.getInstance();
    await Future.wait([
      p.setBool(_kCalFilterWork, s.filterTrabajo),
      p.setBool(_kCalFilterEvents, s.filterEventos),
      p.setBool(_kCalFilterCitas, s.filterCitas),
      p.setBool(_kCalFilterRemind, s.filterRecordatorios),
      p.setBool(_kCalFilterBebe, s.filterBebe),
      p.setBool(_kCalFilterPeriod, s.filterPeriodo),
      p.setBool(_kCalCompact, s.compactMode),
      p.setString(_kCalBgName, s.bgName),
      p.setString(_kCalDesign, s.design),
    ]);
  }
}

/// DTO con todas las preferencias del calendario.
class CalendarSettings {
  final bool filterTrabajo;
  final bool filterEventos;
  final bool filterCitas;
  final bool filterRecordatorios;
  final bool filterBebe;
  final bool filterPeriodo;
  final bool compactMode;
  final String bgName;
  final String design;

  const CalendarSettings({
    required this.filterTrabajo,
    required this.filterEventos,
    required this.filterCitas,
    required this.filterRecordatorios,
    required this.filterBebe,
    required this.filterPeriodo,
    required this.compactMode,
    required this.bgName,
    required this.design,
  });
}
