// lib/core/sync_check_service.dart
//
// Comprueba si la BD local (SQLite / SharedPreferences) y Firebase coinciden,
// módulo a módulo, y los pone al día.
//
// Para cada elemento se compara la versión del móvil con la de la nube:
//
//   · Igual en los dos sitios .................. sincronizado
//   · Solo en el móvil y es MÍO ................ ↑ se SUBE
//   · Solo en el móvil y es de OTRA persona .... ✕ se QUITA del móvil
//                                                (ya no te lo comparten)
//   · Solo en la nube .......................... ↓ se BAJA
//   · Distinto en los dos sitios:
//       - mío y con cambios del móvil pendientes (synced = 0) → ↑ se SUBE
//       - en cualquier otro caso                              → ↓ se BAJA
//       - diario: se COMBINAN los dos textos (no se pierde nada)
//
// Nunca se borra nada de la nube. Los elementos compartidos que ocultaste
// ("Quitar") no se vuelven a bajar.
//
// Gastos no tiene copia local (vive solo en la nube): solo se informa.

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/calendar_category.dart';
import 'db_provider.dart';
import 'db_schema.dart';
import 'dismissed_shared_service.dart';
import 'firebase_sync_service.dart';
import 'weekly_share_service.dart';

// ════════════════════════════════════════════════════════════════════════════
// RESULTADOS
// ════════════════════════════════════════════════════════════════════════════

enum SyncAction { upload, download, removeLocal, merge }

class SyncItem {
  final String id;
  final String title;
  final SyncAction action;
  const SyncItem(this.id, this.title, this.action);
}

class SyncModuleReport {
  final String key;
  final String label;
  final IconData icon;

  /// Elementos distintos entre móvil y nube (sin contar los ocultos).
  final int total;
  final int inSync;

  /// Lo que falta por sincronizar.
  final List<SyncItem> items;

  /// Si no se pudo comprobar (sin conexión, permisos…).
  final String? error;

  /// Texto informativo (p. ej. Gastos, que no tiene copia local).
  final String? info;

  // Datos de la comprobación, para aplicar sin volver a descargar.
  final _SyncModule? _module;
  final Map<String, Map<String, dynamic>> _local;
  final Map<String, Map<String, dynamic>> _cloud;

  SyncModuleReport._({
    required this.key,
    required this.label,
    required this.icon,
    this.total = 0,
    this.inSync = 0,
    this.items = const [],
    this.error,
    this.info,
    _SyncModule? module,
    Map<String, Map<String, dynamic>> local = const {},
    Map<String, Map<String, dynamic>> cloud = const {},
  }) : _module = module,
       _local = local,
       _cloud = cloud;

  bool get isOk => error == null && items.isEmpty;
  bool get hasError => error != null;
  int count(SyncAction a) => items.where((i) => i.action == a).length;
}

class SyncApplyResult {
  final int done;
  final int failed;
  final List<String> errors;
  const SyncApplyResult(this.done, this.failed, this.errors);
}

// ════════════════════════════════════════════════════════════════════════════
// SERVICIO
// ════════════════════════════════════════════════════════════════════════════

class SyncCheckService {
  SyncCheckService._();
  static final SyncCheckService instance = SyncCheckService._();

  static const Duration _readWait = Duration(seconds: 25);
  static const Duration _writeWait = Duration(seconds: 20);

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  final List<_SyncModule> _modules = [
    _EventsModule(),
    _CategoriesModule(),
    _ShiftsModule(),
    _AssignmentsModule(),
    _WeeklyModule.tasks(),
    _WeeklyModule.menus(),
    _WeeklyModule.trainings(),
    _FriendsModule(),
    _DiaryModule(),
  ];

  // ── Comprobar ──────────────────────────────────────────────────────────────

  Future<List<SyncModuleReport>> check({
    void Function(String label)? onProgress,
  }) async {
    final uid = _uid;
    if (uid.isEmpty) throw StateError('No hay sesión iniciada');

    // Deja salir antes lo que el móvil tenga en cola para la nube.
    try {
      await FirebaseFirestore.instance.waitForPendingWrites().timeout(
        const Duration(seconds: 8),
      );
    } catch (_) {}

    final reports = <SyncModuleReport>[];
    for (final m in _modules) {
      onProgress?.call(m.label);
      reports.add(await _checkModule(m, uid));
    }
    onProgress?.call('Gastos');
    reports.add(await _checkExpenses(uid));
    return reports;
  }

  Future<SyncModuleReport> _checkModule(_SyncModule m, String uid) async {
    try {
      final cloud = await m.cloud(uid).timeout(_readWait);
      final local = await m.local(uid);
      final ignored = await m.ignored();

      final items = <SyncItem>[];
      var inSync = 0;
      var total = 0;

      for (final id in {...local.keys, ...cloud.keys}) {
        final l = local[id];
        final c = cloud[id];

        if (l != null && c != null) {
          total++;
          if (_same(m, l, c, uid)) {
            inSync++;
          } else {
            items.add(SyncItem(id, m.titleOf(l), m.resolveConflict(l, uid)));
          }
        } else if (l != null) {
          total++;
          if (m.isOwn(l, uid)) {
            items.add(SyncItem(id, m.titleOf(l), SyncAction.upload));
          } else if (m.keepForeignLocalOnly) {
            inSync++;
          } else {
            items.add(SyncItem(id, m.titleOf(l), SyncAction.removeLocal));
          }
        } else if (c != null) {
          if (ignored.contains(id)) continue; // lo ocultaste: no se baja
          total++;
          items.add(SyncItem(id, m.titleOf(c), SyncAction.download));
        }
      }

      items.sort((a, b) => a.title.compareTo(b.title));
      return SyncModuleReport._(
        key: m.key,
        label: m.label,
        icon: m.icon,
        total: total,
        inSync: inSync,
        items: items,
        module: m,
        local: local,
        cloud: cloud,
      );
    } on TimeoutException {
      return SyncModuleReport._(
        key: m.key,
        label: m.label,
        icon: m.icon,
        error: 'La nube no responde. Revisa la conexión.',
      );
    } catch (e) {
      debugPrint('❌ Comprobación ${m.key}: $e');
      return SyncModuleReport._(
        key: m.key,
        label: m.label,
        icon: m.icon,
        error: _friendlyError(e),
      );
    }
  }

  Future<SyncModuleReport> _checkExpenses(String uid) async {
    const label = 'Gastos';
    const icon = Icons.account_balance_wallet_outlined;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('expense_projects')
          .where('members', arrayContains: uid)
          .get(const GetOptions(source: Source.server))
          .timeout(_readWait);
      final n = snap.docs.length;
      return SyncModuleReport._(
        key: 'expenses',
        label: label,
        icon: icon,
        total: n,
        inSync: n,
        info:
            'Se guardan directamente en la nube (sin copia en el móvil): '
            '$n ${n == 1 ? 'proyecto' : 'proyectos'}.',
      );
    } catch (e) {
      return SyncModuleReport._(
        key: 'expenses',
        label: label,
        icon: icon,
        error: _friendlyError(e),
      );
    }
  }

  // ── Sincronizar ────────────────────────────────────────────────────────────

  Future<SyncApplyResult> apply(
    List<SyncModuleReport> reports, {
    void Function(String label)? onProgress,
  }) async {
    final uid = _uid;
    if (uid.isEmpty) throw StateError('No hay sesión iniciada');

    var done = 0;
    var failed = 0;
    final errors = <String>[];

    for (final r in reports) {
      final m = r._module;
      if (m == null || r.items.isEmpty) continue;
      onProgress?.call(r.label);

      // ↑ Subir (en bloque: algunos módulos suben mejor todo junto)
      final ups = r.items.where((i) => i.action == SyncAction.upload).toList();
      if (ups.isNotEmpty) {
        final pairs = [
          for (final i in ups) _Pair(i.id, r._local[i.id]!, r._cloud[i.id]),
        ];
        final bad = await m.uploadBatch(uid, pairs, _writeWait);
        done += ups.length - bad.length;
        failed += bad.length;
        if (bad.isNotEmpty) {
          errors.add('${r.label}: ${bad.length} sin subir');
        }
      }

      // ↓ Bajar · ✕ Quitar · ⇄ Combinar
      for (final i in r.items.where((i) => i.action != SyncAction.upload)) {
        try {
          switch (i.action) {
            case SyncAction.download:
              await m.saveLocal(r._cloud[i.id]!);
              break;
            case SyncAction.removeLocal:
              await m.removeLocal(i.id);
              break;
            case SyncAction.merge:
              await m
                  .merge(uid, r._local[i.id]!, r._cloud[i.id]!)
                  .timeout(_writeWait);
              break;
            case SyncAction.upload:
              break;
          }
          done++;
        } catch (e) {
          failed++;
          debugPrint('❌ ${r.key}/${i.id}: $e');
        }
      }
    }

    if (failed > 0 && errors.isEmpty) {
      errors.add('$failed cambios no se pudieron aplicar');
    }
    return SyncApplyResult(done, failed, errors);
  }

  // ── Comparación ────────────────────────────────────────────────────────────

  bool _same(
    _SyncModule m,
    Map<String, dynamic> a,
    Map<String, dynamic> b,
    String uid,
  ) {
    for (final c in m.compareCols) {
      if (_norm(c, a[c], uid) != _norm(c, b[c], uid)) return false;
    }
    return true;
  }

  /// Misma representación para los dos lados (null == '', bool == 0/1,
  /// shared_with sin importar el orden, owner vacío == yo).
  static String _norm(String col, dynamic v, String uid) {
    if (col == 'owner_id') return (v == null || v == '') ? uid : '$v';
    if (v == null) return '';
    if (col == 'shared_with') {
      final set = v is List
          ? v.map((e) => '$e').toSet()
          : WeeklyShareService.parseUids('$v');
      return (set.toList()..sort()).join(',');
    }
    if (v is bool) return v ? '1' : '0';
    if (v is num) {
      return v == v.roundToDouble() ? '${v.round()}' : '$v';
    }
    return '$v';
  }

  static String _friendlyError(Object e) {
    final s = '$e';
    if (s.contains('permission-denied')) {
      return 'Sin permiso para leer estos datos (revisa las reglas).';
    }
    if (s.contains('unavailable') || s.contains('offline')) {
      return 'Sin conexión con la nube.';
    }
    return 'No se pudo comprobar.';
  }
}

// ════════════════════════════════════════════════════════════════════════════
// MÓDULOS
// ════════════════════════════════════════════════════════════════════════════

const GetOptions _server = GetOptions(source: Source.server);
FirebaseFirestore get _fs => FirebaseFirestore.instance;

String get _displayName =>
    FirebaseAuth.instance.currentUser?.displayName ??
    FirebaseAuth.instance.currentUser?.email ??
    '';

int? _ms(dynamic ts) => ts is Timestamp ? ts.millisecondsSinceEpoch : null;

Timestamp? _ts(dynamic ms) =>
    ms is int ? Timestamp.fromMillisecondsSinceEpoch(ms) : null;

/// Firestore (List) → formato local '["a","b"]'.
String _listToJson(dynamic raw) {
  if (raw is! List || raw.isEmpty) return '';
  return '[${raw.map((e) => '"$e"').join(',')}]';
}

List<String> _uidsOf(dynamic localJson) =>
    WeeklyShareService.parseUids('${localJson ?? ''}').toList();

String _fmtDayMs(int? ms, {bool utc = false}) {
  if (ms == null || ms == 0) return '';
  final d = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: utc);
  return '${d.day}/${d.month}/${d.year}';
}

Map<String, Map<String, dynamic>> _byId(List<Map<String, dynamic>> rows) => {
  for (final r in rows)
    if ((r['id'] as String?)?.isNotEmpty == true)
      r['id'] as String: Map<String, dynamic>.from(r),
};

Future<void> _markSynced(String table, String id) async {
  final db = await DBProvider.db.database;
  await db.update(table, {'synced': 1}, where: 'id = ?', whereArgs: [id]);
}

class _Pair {
  final String id;
  final Map<String, dynamic> local;
  final Map<String, dynamic>? cloud;
  const _Pair(this.id, this.local, this.cloud);
}

abstract class _SyncModule {
  String get key;
  String get label;
  IconData get icon;
  List<String> get compareCols;

  /// ¿La tabla local tiene 'synced' (0 = cambio del móvil pendiente)?
  bool get hasSyncedFlag => false;

  /// Si un elemento AJENO está solo en el móvil, ¿se deja? (si no, se quita)
  bool get keepForeignLocalOnly => false;

  Future<Map<String, Map<String, dynamic>>> cloud(String uid);
  Future<Map<String, Map<String, dynamic>>> local(String uid);
  Future<Set<String>> ignored() async => const {};

  String titleOf(Map<String, dynamic> row);

  bool isOwn(Map<String, dynamic> row, String uid) {
    final o = row['owner_id'];
    return o == null || o == '' || o == uid;
  }

  /// Qué hacer cuando el elemento existe en los dos sitios pero difiere.
  SyncAction resolveConflict(Map<String, dynamic> local, String uid) {
    final pending = hasSyncedFlag && (local['synced'] ?? 1) == 0;
    if (pending && (isOwn(local, uid) || canUploadForeign)) {
      return SyncAction.upload;
    }
    return SyncAction.download;
  }

  /// ¿Puede un receptor subir su parte de un elemento ajeno?
  bool get canUploadForeign => false;

  Future<void> saveLocal(Map<String, dynamic> cloudRow);
  Future<void> removeLocal(String id);

  /// Sube un elemento. [cloud] puede ser null (solo estaba en el móvil).
  Future<void> upload(
    String uid,
    Map<String, dynamic> local,
    Map<String, dynamic>? cloud,
  );

  Future<void> merge(
    String uid,
    Map<String, dynamic> local,
    Map<String, dynamic> cloud,
  ) async {}

  /// Sube varios en tandas. Devuelve los ids que fallaron.
  Future<Set<String>> uploadBatch(
    String uid,
    List<_Pair> pairs,
    Duration wait,
  ) async {
    final failed = <String>{};
    const chunk = 10;
    for (var i = 0; i < pairs.length; i += chunk) {
      await Future.wait(
        pairs.skip(i).take(chunk).map((p) async {
          try {
            await upload(uid, p.local, p.cloud).timeout(wait);
          } catch (e) {
            debugPrint('❌ Subir $key/${p.id}: $e');
            failed.add(p.id);
          }
        }),
      );
    }
    return failed;
  }
}

// ── Eventos del calendario (compartidos, propios y privados) ────────────────

class _EventsModule extends _SyncModule {
  @override
  String get key => 'events';
  @override
  String get label => 'Eventos del calendario';
  @override
  IconData get icon => Icons.event;
  @override
  bool get hasSyncedFlag => true;
  @override
  List<String> get compareCols => const [
    'title',
    'description',
    'date',
    'from_minutes',
    'to_minutes',
    'category',
    'tipo',
    'icon',
    'creator',
    'users',
    'color',
    'owner_id',
    'has_alarm',
    'alarm_at',
    'has_notification',
    'notification_at',
    'solo_para_mi',
  ];

  final Map<String, List<Map<String, dynamic>>> _checklists = {};

  @override
  Future<Map<String, Map<String, dynamic>>> cloud(String uid) async {
    final col = _fs.collection('events');
    final own = await col.where('owner_id', isEqualTo: uid).get(_server);
    final shared = await col
        .where('shared_with', arrayContains: uid)
        .get(_server);
    final private = await _fs
        .collection('users')
        .doc(uid)
        .collection('private_events')
        .get(_server);

    _checklists.clear();
    final rows = <String, Map<String, dynamic>>{};
    void add(QueryDocumentSnapshot<Map<String, dynamic>> d, bool isPrivate) {
      if (rows.containsKey(d.id)) return;
      final x = d.data();
      rows[d.id] = {
        'id': d.id,
        'title': x['title'] ?? '',
        'description': x['description'] ?? '',
        'date': _ms(x['date']) ?? 0,
        'from_minutes': x['from_minutes'] ?? 0,
        'to_minutes': x['to_minutes'] ?? 60,
        'category': x['category'] ?? 'Evento',
        'tipo': x['tipo'] ?? 'Otros',
        'icon': x['icon'] ?? '',
        'creator': x['creator'] ?? '',
        'users': x['users'] ?? '',
        'color': x['color'] ?? 4280391411,
        'owner_id': isPrivate ? uid : (x['owner_id'] ?? uid),
        'synced': 1,
        'has_alarm': (x['has_alarm'] ?? false) == true ? 1 : 0,
        'alarm_at': _ms(x['alarm_at']),
        'has_notification': (x['has_notification'] ?? false) == true ? 1 : 0,
        'notification_at': _ms(x['notification_at']),
        'solo_para_mi': isPrivate || x['solo_para_mi'] == true ? 1 : 0,
      };
      final embedded = x['checklist_items'];
      if (embedded is Map && embedded.isNotEmpty) {
        _checklists[d.id] = [
          for (final e in embedded.entries)
            if (e.value is Map)
              {
                'id': '${e.key}',
                'event_id': d.id,
                'text': (e.value as Map)['text'] ?? '',
                'is_checked': (e.value as Map)['is_checked'] == true ? 1 : 0,
                'position': (e.value as Map)['position'] ?? 0,
              },
        ];
      }
    }

    for (final d in own.docs) {
      add(d, false);
    }
    for (final d in shared.docs) {
      add(d, false);
    }
    for (final d in private.docs) {
      add(d, true);
    }
    return rows;
  }

  @override
  Future<Map<String, Map<String, dynamic>>> local(String uid) async =>
      _byId(await DBProvider.db.getAll(DBSchema.tableEvents));

  @override
  String titleOf(Map<String, dynamic> r) {
    final t = '${r['title'] ?? ''}'.trim();
    final d = _fmtDayMs(r['date'] as int?, utc: true);
    return [
      if (t.isNotEmpty) t else 'Evento sin título',
      if (d.isNotEmpty) d,
    ].join(' · ');
  }

  @override
  Future<void> saveLocal(Map<String, dynamic> row) async {
    await DBProvider.db.insertOrReplace(DBSchema.tableEvents, row);
    final items = _checklists[row['id']];
    if (items != null && items.isNotEmpty) {
      await DBProvider.db.delete(
        DBSchema.tableChecklist,
        where: 'event_id = ?',
        whereArgs: [row['id']],
      );
      await DBProvider.db.batchInsert(DBSchema.tableChecklist, items);
    }
  }

  @override
  Future<void> removeLocal(String id) async {
    await DBProvider.db.delete(
      DBSchema.tableEvents,
      where: 'id = ?',
      whereArgs: [id],
    );
    await DBProvider.db.delete(
      DBSchema.tableChecklist,
      where: 'event_id = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<void> upload(
    String uid,
    Map<String, dynamic> local,
    Map<String, dynamic>? cloud,
  ) async {
    // No se usa: los eventos se suben en bloque (uploadBatch).
  }

  /// Reutiliza la subida del calendario (compartidos, privados, categoría,
  /// checklist…): se marcan como pendientes y se suben con pushPendingEvents.
  @override
  Future<Set<String>> uploadBatch(
    String uid,
    List<_Pair> pairs,
    Duration wait,
  ) async {
    final ids = pairs.map((p) => p.id).toList();
    final db = await DBProvider.db.database;
    for (final id in ids) {
      await db.update(
        DBSchema.tableEvents,
        {'synced': 0},
        where: 'id = ?',
        whereArgs: [id],
      );
    }
    try {
      await FirebaseSyncService.instance
          .pushPendingEvents(uid)
          .timeout(wait * 3);
    } catch (e) {
      debugPrint('❌ Subida de eventos: $e');
    }
    final failed = <String>{};
    for (final id in ids) {
      final rows = await DBProvider.db.query(
        DBSchema.tableEvents,
        where: 'id = ? AND synced = 0',
        whereArgs: [id],
        limit: '1',
      );
      if (rows.isNotEmpty) failed.add(id);
    }
    return failed;
  }
}

// ── Categorías personalizadas ────────────────────────────────────────────────

class _CategoriesModule extends _SyncModule {
  @override
  String get key => 'categories';
  @override
  String get label => 'Categorías del calendario';
  @override
  IconData get icon => Icons.label_outline;
  @override
  bool get hasSyncedFlag => true;
  @override
  bool get keepForeignLocalOnly => true; // las importadas de amigos se quedan
  @override
  List<String> get compareCols => const ['label', 'color', 'icon', 'owner_id'];

  @override
  Future<Map<String, Map<String, dynamic>>> cloud(String uid) async {
    final col = _fs.collection('calendar_categories');
    final own = await col.where('owner_id', isEqualTo: uid).get(_server);
    final shared = await col
        .where('shared_with', arrayContains: uid)
        .get(_server);
    final rows = <String, Map<String, dynamic>>{};
    for (final d in [...own.docs, ...shared.docs]) {
      final x = d.data();
      if (x['key'] is! String) continue;
      final row = CalendarCategory.fromFirestore(
        x,
      ).copyWith(synced: true).toMap();
      rows.putIfAbsent(row['id'] as String, () => row);
    }
    return rows;
  }

  @override
  Future<Map<String, Map<String, dynamic>>> local(String uid) async =>
      _byId(await DBProvider.db.getAll(DBSchema.tableCalendarCategories));

  @override
  String titleOf(Map<String, dynamic> r) =>
      '${r['icon'] ?? ''} ${r['label'] ?? ''}'.trim();

  @override
  Future<void> saveLocal(Map<String, dynamic> row) =>
      DBProvider.db.insertOrReplace(DBSchema.tableCalendarCategories, row);

  @override
  Future<void> removeLocal(String id) => DBProvider.db.delete(
    DBSchema.tableCalendarCategories,
    where: 'id = ?',
    whereArgs: [id],
  );

  @override
  Future<void> upload(
    String uid,
    Map<String, dynamic> local,
    Map<String, dynamic>? cloud,
  ) async {
    final cat = CalendarCategory.fromMap(local);
    await _fs.collection('calendar_categories').doc('${uid}_${cat.key}').set({
      ...cat.toFirestore(),
      'owner_id': uid,
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await _markSynced(DBSchema.tableCalendarCategories, cat.key);
  }
}

// ── Turnos (definiciones) ────────────────────────────────────────────────────

class _ShiftsModule extends _SyncModule {
  @override
  String get key => 'shifts';
  @override
  String get label => 'Turnos';
  @override
  IconData get icon => Icons.work_history;
  @override
  List<String> get compareCols => const [
    'name',
    'color',
    'from_minutes',
    'to_minutes',
    'euro_per_hour',
    'sort_order',
  ];

  @override
  bool isOwn(Map<String, dynamic> row, String uid) => true;

  @override
  Future<Map<String, Map<String, dynamic>>> cloud(String uid) async {
    final snap = await _fs
        .collection('shifts')
        .where('owner_id', isEqualTo: uid)
        .get(_server);
    return {
      for (final d in snap.docs)
        d.id: {
          'id': d.id,
          'name': d.data()['name'] ?? '',
          'color': d.data()['color'] ?? 4280391411,
          'from_minutes': d.data()['from_minutes'] ?? 0,
          'to_minutes': d.data()['to_minutes'] ?? 0,
          'euro_per_hour': d.data()['euro_per_hour'],
          'sort_order': d.data()['sort_order'] ?? 0,
        },
    };
  }

  @override
  Future<Map<String, Map<String, dynamic>>> local(String uid) async =>
      _byId(await DBProvider.db.getAll(DBSchema.tableShifts));

  @override
  String titleOf(Map<String, dynamic> r) => '${r['name'] ?? 'Turno'}';

  @override
  Future<void> saveLocal(Map<String, dynamic> row) =>
      DBProvider.db.insertOrReplace(DBSchema.tableShifts, row);

  @override
  Future<void> removeLocal(String id) => DBProvider.db.delete(
    DBSchema.tableShifts,
    where: 'id = ?',
    whereArgs: [id],
  );

  @override
  Future<void> upload(
    String uid,
    Map<String, dynamic> l,
    Map<String, dynamic>? cloud,
  ) async {
    await _fs.collection('shifts').doc(l['id'] as String).set({
      'name': l['name'] ?? '',
      'color': l['color'] ?? 4280391411,
      'from_minutes': l['from_minutes'] ?? 0,
      'to_minutes': l['to_minutes'] ?? 0,
      'euro_per_hour': l['euro_per_hour'],
      'sort_order': l['sort_order'] ?? 0,
      'owner_id': uid,
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}

// ── Turnos asignados en el calendario (propios y compartidos conmigo) ────────

class _AssignmentsModule extends _SyncModule {
  @override
  String get key => 'shift_assignments';
  @override
  String get label => 'Turnos del calendario';
  @override
  IconData get icon => Icons.calendar_month_outlined;
  @override
  List<String> get compareCols => const [
    'shift_id',
    'date',
    'owner_id',
    'shift_name',
    'shift_color',
    'shift_from_minutes',
    'shift_to_minutes',
  ];

  List<String>? _shareUids;

  @override
  Future<Map<String, Map<String, dynamic>>> cloud(String uid) async {
    final col = _fs.collection('shift_assignments');
    final own = await col.where('owner_id', isEqualTo: uid).get(_server);
    final shared = await col
        .where('shared_with', arrayContains: uid)
        .get(_server);
    final rows = <String, Map<String, dynamic>>{};
    for (final d in [...own.docs, ...shared.docs]) {
      final x = d.data();
      rows.putIfAbsent(
        d.id,
        () => {
          'id': d.id,
          'shift_id': x['shift_id'] ?? '',
          'date': _ms(x['date']) ?? 0,
          'owner_id': x['owner_id'] ?? uid,
          'shift_name': x['shift_name'] ?? '',
          'shift_color': x['shift_color'] ?? 0xFF2196F3,
          'shift_from_minutes': x['shift_from_minutes'] ?? 0,
          'shift_to_minutes': x['shift_to_minutes'] ?? 0,
        },
      );
    }
    return rows;
  }

  @override
  Future<Map<String, Map<String, dynamic>>> local(String uid) async =>
      _byId(await DBProvider.db.getAll(DBSchema.tableShiftAssignments));

  @override
  String titleOf(Map<String, dynamic> r) {
    final n = '${r['shift_name'] ?? ''}'.trim();
    final d = _fmtDayMs(r['date'] as int?, utc: true);
    return '${n.isNotEmpty ? n : 'Turno'}${d.isNotEmpty ? ' · $d' : ''}';
  }

  @override
  Future<void> saveLocal(Map<String, dynamic> row) =>
      DBProvider.db.insertOrReplace(DBSchema.tableShiftAssignments, row);

  @override
  Future<void> removeLocal(String id) => DBProvider.db.delete(
    DBSchema.tableShiftAssignments,
    where: 'id = ?',
    whereArgs: [id],
  );

  /// Con quién comparto mis turnos (igual que al crearlos).
  Future<List<String>> _turnosShares(String uid) async {
    if (_shareUids != null) return _shareUids!;
    final snap = await _fs
        .collection('calendar_shares')
        .where('from_uid', isEqualTo: uid)
        .get(_server);
    _shareUids = [
      for (final d in snap.docs)
        if (List<String>.from(
              d.data()['categories'] ?? const [],
            ).any((c) => c.toLowerCase() == 'turnos') &&
            (d.data()['to_uid'] as String?)?.isNotEmpty == true)
          d.data()['to_uid'] as String,
    ];
    return _shareUids!;
  }

  @override
  Future<Set<String>> uploadBatch(
    String uid,
    List<_Pair> pairs,
    Duration wait,
  ) async {
    _shareUids = null; // se recalcula una vez por sincronización
    return super.uploadBatch(uid, pairs, wait);
  }

  @override
  Future<void> upload(
    String uid,
    Map<String, dynamic> l,
    Map<String, dynamic>? cloud,
  ) async {
    await _fs.collection('shift_assignments').doc(l['id'] as String).set({
      'shift_id': l['shift_id'] ?? '',
      'date': _ts(l['date']),
      'owner_id': uid,
      'shared_with': await _turnosShares(uid),
      'shift_name': l['shift_name'] ?? '',
      'shift_color': l['shift_color'] ?? 0xFF2196F3,
      'shift_from_minutes': l['shift_from_minutes'] ?? 0,
      'shift_to_minutes': l['shift_to_minutes'] ?? 0,
      'updated_at': FieldValue.serverTimestamp(),
    });
  }
}

// ── Menús / Tareas / Entrenamientos semanales ────────────────────────────────

class _WeeklyModule extends _SyncModule {
  final String type; // 'tasks' | 'menus' | 'trainings'
  final String collection;
  final String table;
  @override
  final String label;
  @override
  final IconData icon;
  @override
  final List<String> compareCols;
  final Map<String, dynamic> Function(String id, Map<String, dynamic> x)
  _fromCloud;
  final Map<String, dynamic> Function(Map<String, dynamic> l, String uid)
  _ownPayload;

  /// Campos que un RECEPTOR puede cambiar en un elemento ajeno.
  final List<String> foreignFields;

  _WeeklyModule._({
    required this.type,
    required this.collection,
    required this.table,
    required this.label,
    required this.icon,
    required this.compareCols,
    required Map<String, dynamic> Function(String, Map<String, dynamic>)
    fromCloud,
    required Map<String, dynamic> Function(Map<String, dynamic>, String)
    ownPayload,
    required this.foreignFields,
  }) : _fromCloud = fromCloud,
       _ownPayload = ownPayload;

  factory _WeeklyModule.tasks() => _WeeklyModule._(
    type: 'tasks',
    collection: 'weekly_tasks',
    table: DBSchema.tableWeeklyTasks,
    label: 'Tareas semanales',
    icon: Icons.checklist_rtl,
    compareCols: const [
      'date',
      'title',
      'description',
      'is_done',
      'owner_id',
      'shared_with',
      'recurrence',
      'parent_id',
    ],
    fromCloud: (id, x) => {
      'id': id,
      'date': _ms(x['date']) ?? 0,
      'title': x['title'] ?? '',
      'description': x['description'] ?? '',
      'is_done': x['is_done'] == true ? 1 : 0,
      'owner_id': x['owner_id'] ?? '',
      'owner_name': x['owner_name'] ?? '',
      'shared_with': _listToJson(x['shared_with']),
      'recurrence': x['recurrence'] ?? 'none',
      'parent_id': x['parent_id'] ?? '',
      'synced': 1,
    },
    ownPayload: (l, uid) => {
      'date': _ts(l['date']),
      'title': l['title'] ?? '',
      'description': l['description'] ?? '',
      'is_done': l['is_done'] == 1,
      'owner_id': uid,
      'owner_name': _displayName,
      'shared_with': _uidsOf(l['shared_with']),
      'recurrence': l['recurrence'] ?? 'none',
      'parent_id': l['parent_id'] ?? '',
      'updated_at': FieldValue.serverTimestamp(),
    },
    foreignFields: const ['is_done'],
  );

  factory _WeeklyModule.menus() => _WeeklyModule._(
    type: 'menus',
    collection: 'weekly_menus',
    table: DBSchema.tableWeeklyMenus,
    label: 'Menú semanal',
    icon: Icons.restaurant_menu,
    compareCols: const [
      'date',
      'meal_type',
      'title',
      'description',
      'owner_id',
      'shared_with',
    ],
    fromCloud: (id, x) => {
      'id': id,
      'date': _ms(x['date']) ?? 0,
      'meal_type': x['meal_type'] ?? 'Comida',
      'title': x['title'] ?? '',
      'description': x['description'] ?? '',
      'owner_id': x['owner_id'] ?? '',
      'owner_name': x['owner_name'] ?? '',
      'shared_with': _listToJson(x['shared_with']),
      'synced': 1,
    },
    ownPayload: (l, uid) => {
      'date': _ts(l['date']),
      'meal_type': l['meal_type'] ?? 'Comida',
      'title': l['title'] ?? '',
      'description': l['description'] ?? '',
      'owner_id': uid,
      'owner_name': _displayName,
      'shared_with': _uidsOf(l['shared_with']),
      'updated_at': FieldValue.serverTimestamp(),
    },
    foreignFields: const ['meal_type', 'title', 'description'],
  );

  factory _WeeklyModule.trainings() => _WeeklyModule._(
    type: 'trainings',
    collection: 'weekly_trainings',
    table: DBSchema.tableWeeklyTrainings,
    label: 'Entrenamiento',
    icon: Icons.fitness_center,
    compareCols: const [
      'date',
      'training_type',
      'title',
      'description',
      'is_done',
      'owner_id',
      'shared_with',
      'image_data',
    ],
    fromCloud: (id, x) => {
      'id': id,
      'date': _ms(x['date']) ?? 0,
      'training_type': x['training_type'] ?? 'Otro',
      'title': x['title'] ?? '',
      'description': x['description'] ?? '',
      'is_done': x['is_done'] == true ? 1 : 0,
      'owner_id': x['owner_id'] ?? '',
      'owner_name': x['owner_name'] ?? '',
      'shared_with': _listToJson(x['shared_with']),
      'synced': 1,
      'image_data': x['image_data'] ?? '',
    },
    ownPayload: (l, uid) => {
      'date': _ts(l['date']),
      'training_type': l['training_type'] ?? 'Otro',
      'title': l['title'] ?? '',
      'description': l['description'] ?? '',
      'is_done': l['is_done'] == 1,
      'owner_id': uid,
      'owner_name': _displayName,
      'shared_with': _uidsOf(l['shared_with']),
      'image_data': l['image_data'] ?? '',
      'updated_at': FieldValue.serverTimestamp(),
    },
    foreignFields: const ['is_done'],
  );

  @override
  String get key => type;
  @override
  bool get hasSyncedFlag => true;
  @override
  bool get canUploadForeign => true;

  @override
  Future<Map<String, Map<String, dynamic>>> cloud(String uid) async {
    final col = _fs.collection(collection);
    final own = await col.where('owner_id', isEqualTo: uid).get(_server);
    final shared = await col
        .where('shared_with', arrayContains: uid)
        .get(_server);
    final rows = <String, Map<String, dynamic>>{};
    for (final d in [...own.docs, ...shared.docs]) {
      rows.putIfAbsent(d.id, () => _fromCloud(d.id, d.data()));
    }
    return rows;
  }

  @override
  Future<Map<String, Map<String, dynamic>>> local(String uid) async =>
      _byId(await DBProvider.db.getAll(table));

  @override
  Future<Set<String>> ignored() =>
      DismissedSharedService.instance.idsForType(type);

  @override
  String titleOf(Map<String, dynamic> r) {
    final t = '${r['title'] ?? ''}'.trim();
    final d = _fmtDayMs(r['date'] as int?);
    return [
      if (t.isNotEmpty) t else 'Sin título',
      if (d.isNotEmpty) d,
    ].join(' · ');
  }

  @override
  Future<void> saveLocal(Map<String, dynamic> row) =>
      DBProvider.db.insertOrReplace(table, row);

  @override
  Future<void> removeLocal(String id) =>
      DBProvider.db.delete(table, where: 'id = ?', whereArgs: [id]);

  @override
  Future<void> upload(
    String uid,
    Map<String, dynamic> l,
    Map<String, dynamic>? cloud,
  ) async {
    final id = l['id'] as String;
    final ref = _fs.collection(collection).doc(id);

    if (isOwn(l, uid)) {
      await ref.set(_ownPayload(l, uid), SetOptions(merge: true));
      await _markSynced(table, id);
      return;
    }

    // Ajeno: solo lo que un receptor puede cambiar; el resto, lo de la nube.
    final data = <String, dynamic>{
      for (final f in foreignFields)
        f: f == 'is_done' ? l[f] == 1 : (l[f] ?? ''),
      'updated_at': FieldValue.serverTimestamp(),
    };
    await ref.set(data, SetOptions(merge: true));
    if (cloud != null) {
      await saveLocal({
        ...cloud,
        for (final f in foreignFields) f: l[f],
        'synced': 1,
      });
    } else {
      await _markSynced(table, id);
    }
  }
}

// ── Amigos ───────────────────────────────────────────────────────────────────

class _FriendsModule extends _SyncModule {
  @override
  String get key => 'friends';
  @override
  String get label => 'Amigos';
  @override
  IconData get icon => Icons.group;
  @override
  List<String> get compareCols => const [
    'name',
    'email',
    'alias',
    'logo',
    'firebase_uid',
  ];

  @override
  bool isOwn(Map<String, dynamic> row, String uid) => true;

  @override
  Future<Map<String, Map<String, dynamic>>> cloud(String uid) async {
    final snap = await _fs
        .collection('friends')
        .where('owner_id', isEqualTo: uid)
        .get(_server);
    return {
      for (final d in snap.docs)
        d.id: {
          'id': d.id,
          'name': d.data()['name'] ?? '',
          'email': d.data()['email'] ?? '',
          'alias': d.data()['alias'] ?? '',
          'logo': d.data()['logo'] ?? '😊',
          'firebase_uid': d.data()['friend_uid'],
        },
    };
  }

  @override
  Future<Map<String, Map<String, dynamic>>> local(String uid) async {
    final rows = await DBProvider.db.getAll(DBSchema.tableFriends);
    // Solo las columnas que se sincronizan (la tabla tiene alguna más).
    return _byId([
      for (final r in rows)
        {
          'id': r['id'],
          'name': r['name'] ?? '',
          'email': r['email'] ?? '',
          'alias': r['alias'] ?? '',
          'logo': r['logo'] ?? '😊',
          'firebase_uid': r['firebase_uid'],
        },
    ]);
  }

  @override
  String titleOf(Map<String, dynamic> r) {
    final a = '${r['alias'] ?? ''}'.trim();
    return a.isNotEmpty ? a : '${r['name'] ?? r['email'] ?? 'Amigo'}';
  }

  @override
  Future<void> saveLocal(Map<String, dynamic> row) =>
      DBProvider.db.insertOrReplace(DBSchema.tableFriends, row);

  @override
  Future<void> removeLocal(String id) => DBProvider.db.delete(
    DBSchema.tableFriends,
    where: 'id = ?',
    whereArgs: [id],
  );

  @override
  Future<void> upload(
    String uid,
    Map<String, dynamic> l,
    Map<String, dynamic>? cloud,
  ) async {
    await _fs.collection('friends').doc(l['id'] as String).set({
      'name': l['name'] ?? '',
      'email': l['email'] ?? '',
      'alias': l['alias'] ?? '',
      'logo': l['logo'] ?? '😊',
      'friend_uid': l['firebase_uid'],
      'owner_id': uid,
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}

// ── Diario (móvil: SharedPreferences · nube: users/{uid}/diary) ─────────────

class _DiaryModule extends _SyncModule {
  @override
  String get key => 'diary';
  @override
  String get label => 'Diario';
  @override
  IconData get icon => Icons.menu_book_outlined;
  @override
  List<String> get compareCols => const ['text'];

  static const String _separator =
      '\n\n──── Versión de otro dispositivo ────\n';

  String _prefix(String uid) => 'diary_${uid}_';

  CollectionReference<Map<String, dynamic>> _col(String uid) =>
      _fs.collection('users').doc(uid).collection('diary');

  @override
  bool isOwn(Map<String, dynamic> row, String uid) => true;

  /// Si el día se escribió en los dos sitios con textos distintos, se
  /// combinan: no se pierde nada.
  @override
  SyncAction resolveConflict(Map<String, dynamic> local, String uid) =>
      SyncAction.merge;

  @override
  Future<Map<String, Map<String, dynamic>>> cloud(String uid) async {
    final snap = await _col(uid).get(_server);
    return {
      for (final d in snap.docs)
        if (!d.id.startsWith('pin') &&
            '${d.data()['text'] ?? ''}'.trim().isNotEmpty)
          d.id: {'id': d.id, 'text': '${d.data()['text']}'},
    };
  }

  @override
  Future<Map<String, Map<String, dynamic>>> local(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    final prefix = _prefix(uid);
    final out = <String, Map<String, dynamic>>{};
    for (final k in prefs.getKeys().where((k) => k.startsWith(prefix))) {
      final text = prefs.getString(k) ?? '';
      if (text.trim().isEmpty) continue;
      final day = k.substring(prefix.length);
      out[day] = {'id': day, 'text': text};
    }
    return out;
  }

  @override
  String titleOf(Map<String, dynamic> r) {
    final p = '${r['id']}'.split('_');
    if (p.length == 3) {
      return '${int.tryParse(p[2]) ?? p[2]}/${int.tryParse(p[1]) ?? p[1]}/${p[0]}';
    }
    return '${r['id']}';
  }

  Future<void> _saveLocalText(String uid, String day, String text) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('${_prefix(uid)}$day', text);
  }

  @override
  Future<void> saveLocal(Map<String, dynamic> row) async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    await _saveLocalText(uid, row['id'] as String, '${row['text']}');
  }

  @override
  Future<void> removeLocal(String id) async {}

  @override
  Future<void> upload(
    String uid,
    Map<String, dynamic> l,
    Map<String, dynamic>? cloud,
  ) async {
    await _col(uid).doc(l['id'] as String).set({'text': '${l['text']}'});
  }

  @override
  Future<void> merge(
    String uid,
    Map<String, dynamic> local,
    Map<String, dynamic> cloud,
  ) async {
    final l = '${local['text']}';
    final c = '${cloud['text']}';
    final String result;
    if (c.contains(l)) {
      result = c; // la nube ya incluye lo del móvil
    } else if (l.contains(c)) {
      result = l; // el móvil ya incluye lo de la nube
    } else {
      result = '$l$_separator$c';
    }
    final day = local['id'] as String;
    if (result != l) await _saveLocalText(uid, day, result);
    if (result != c) await _col(uid).doc(day).set({'text': result});
  }
}
