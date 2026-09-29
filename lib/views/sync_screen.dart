// lib/views/sync_screen.dart
//
// Ajustes → "Sincronizar datos".
// Comprueba, módulo a módulo, si lo que hay en el móvil coincide con lo que
// hay en la nube (Firebase) y permite ponerlo al día con un botón.
//
// La lógica está en SyncCheckService; esta pantalla solo la muestra.

import 'package:flutter/material.dart';
import '../core/sync_check_service.dart';

class SyncScreen extends StatefulWidget {
  const SyncScreen({super.key});

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  /// Máximo de elementos listados por tipo de cambio dentro de cada módulo.
  static const int _maxItemsShown = 30;

  List<SyncModuleReport>? _reports;
  bool _checking = false;
  bool _applying = false;
  String? _progress;
  String? _fatal;
  DateTime? _checkedAt;
  SyncApplyResult? _lastResult;

  bool get _busy => _checking || _applying;

  int get _pending => _reports?.fold<int>(0, (a, r) => a + r.items.length) ?? 0;

  int get _modulesWithError => _reports?.where((r) => r.hasError).length ?? 0;

  int _total(SyncAction a) =>
      _reports?.fold<int>(0, (s, r) => s + r.count(a)) ?? 0;

  @override
  void initState() {
    super.initState();
    _check();
  }

  // ── Acciones ───────────────────────────────────────────────────────────────

  Future<void> _check() async {
    if (_busy) return;
    setState(() {
      _checking = true;
      _progress = null;
      _fatal = null;
    });
    try {
      final reports = await SyncCheckService.instance.check(
        onProgress: (label) {
          if (mounted) setState(() => _progress = label);
        },
      );
      if (!mounted) return;
      setState(() {
        _reports = reports;
        _checkedAt = DateTime.now();
      });
    } catch (e) {
      debugPrint('❌ Comprobación de sincronización: $e');
      if (!mounted) return;
      setState(() {
        _fatal = e is StateError
            ? e.message
            : 'No se pudo comprobar la sincronización. Inténtalo de nuevo.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _checking = false;
          _progress = null;
        });
      }
    }
  }

  Future<void> _apply() async {
    final reports = _reports;
    if (reports == null || _pending == 0 || _busy) return;

    final ok = await _confirmApply();
    if (ok != true || !mounted) return;

    setState(() {
      _applying = true;
      _progress = null;
    });

    SyncApplyResult? result;
    try {
      result = await SyncCheckService.instance.apply(
        reports,
        onProgress: (label) {
          if (mounted) setState(() => _progress = label);
        },
      );
    } catch (e) {
      debugPrint('❌ Sincronización: $e');
    } finally {
      if (mounted) {
        setState(() {
          _applying = false;
          _progress = null;
        });
      }
    }
    if (!mounted) return;

    setState(() => _lastResult = result);
    if (result == null) {
      _snack('No se pudo sincronizar. Revisa la conexión.', error: true);
    } else if (result.failed == 0) {
      _snack(
        '${result.done} ${result.done == 1 ? 'cambio aplicado' : 'cambios aplicados'}.',
      );
    } else {
      _snack(
        '${result.done} aplicados, ${result.failed} con error. '
        'Vuelve a intentarlo con mejor conexión.',
        error: true,
      );
    }

    // Vuelve a comprobar para enseñar cómo ha quedado.
    await _check();
  }

  Future<bool?> _confirmApply() {
    final up = _total(SyncAction.upload);
    final down = _total(SyncAction.download);
    final merge = _total(SyncAction.merge);
    final remove = _total(SyncAction.removeLocal);

    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sincronizar ahora'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (up > 0) _confirmLine(SyncAction.upload, up),
            if (down > 0) _confirmLine(SyncAction.download, down),
            if (merge > 0) _confirmLine(SyncAction.merge, merge),
            if (remove > 0) _confirmLine(SyncAction.removeLocal, remove),
            const SizedBox(height: 12),
            Text(
              'En la nube no se borra nada.',
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sincronizar'),
          ),
        ],
      ),
    );
  }

  Widget _confirmLine(SyncAction a, int n) {
    final m = _meta(a);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(m.icon, size: 20, color: m.color),
          const SizedBox(width: 10),
          Expanded(child: Text('$n ${m.verbPlural(n)}')),
        ],
      ),
    );
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? Colors.red.shade600 : null,
      ),
    );
  }

  // ── Textos / estilos ───────────────────────────────────────────────────────

  _ActionMeta _meta(SyncAction a) => switch (a) {
    SyncAction.upload => const _ActionMeta(
      icon: Icons.cloud_upload_outlined,
      color: Colors.blue,
      arrow: '↑',
      short: 'subir',
      header: 'Se subirán a la nube',
      singular: 'elemento se subirá a la nube',
      plural: 'elementos se subirán a la nube',
    ),
    SyncAction.download => const _ActionMeta(
      icon: Icons.cloud_download_outlined,
      color: Colors.teal,
      arrow: '↓',
      short: 'bajar',
      header: 'Se bajarán al móvil',
      singular: 'elemento se bajará al móvil',
      plural: 'elementos se bajarán al móvil',
    ),
    SyncAction.merge => const _ActionMeta(
      icon: Icons.merge_type,
      color: Colors.purple,
      arrow: '⇄',
      short: 'combinar',
      header: 'Se combinarán los dos textos',
      singular: 'día del diario se combinará',
      plural: 'días del diario se combinarán',
    ),
    SyncAction.removeLocal => const _ActionMeta(
      icon: Icons.remove_circle_outline,
      color: Colors.deepOrange,
      arrow: '✕',
      short: 'quitar',
      header: 'Se quitarán del móvil (ya no te los comparten)',
      singular: 'elemento se quitará del móvil (ya no te lo comparten)',
      plural: 'elementos se quitarán del móvil (ya no te los comparten)',
    ),
  };

  static const List<SyncAction> _order = [
    SyncAction.upload,
    SyncAction.download,
    SyncAction.merge,
    SyncAction.removeLocal,
  ];

  String _countsText(SyncModuleReport r) {
    final parts = <String>[
      for (final a in _order)
        if (r.count(a) > 0) '${_meta(a).arrow} ${r.count(a)} ${_meta(a).short}',
    ];
    if (r.inSync > 0) parts.add('${r.inSync} al día');
    return parts.join(' · ');
  }

  String _hhmm(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  // ── UI ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final reports = _reports;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sincronización'),
        actions: [
          IconButton(
            tooltip: 'Comprobar de nuevo',
            icon: const Icon(Icons.refresh),
            onPressed: _busy ? null : _check,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_busy) const LinearProgressIndicator(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(top: 8, bottom: 16),
              children: [
                _statusCard(),
                if (reports != null) ...[
                  const SizedBox(height: 4),
                  for (final r in reports) _moduleCard(r),
                ],
                const SizedBox(height: 8),
                _rulesCard(),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _check,
                  icon: const Icon(Icons.fact_check_outlined),
                  label: const Text('Comprobar'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: (_busy || _pending == 0) ? null : _apply,
                  icon: const Icon(Icons.sync),
                  label: Text(
                    _pending > 0 ? 'Sincronizar ($_pending)' : 'Sincronizar',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Tarjeta de estado general ──────────────────────────────────────────────

  Widget _statusCard() {
    final theme = Theme.of(context);

    late final IconData icon;
    late final Color color;
    late final String title;
    final lines = <String>[];

    if (_fatal != null) {
      icon = Icons.error_outline;
      color = Colors.red;
      title = _fatal!;
    } else if (_reports == null) {
      icon = Icons.sync;
      color = theme.colorScheme.primary;
      title = 'Comprobando…';
      if (_progress != null) lines.add(_progress!);
    } else {
      final pending = _pending;
      final errors = _modulesWithError;
      if (_applying) {
        icon = Icons.sync;
        color = theme.colorScheme.primary;
        title = 'Sincronizando…';
        if (_progress != null) lines.add(_progress!);
      } else if (_checking) {
        icon = Icons.sync;
        color = theme.colorScheme.primary;
        title = 'Comprobando…';
        if (_progress != null) lines.add(_progress!);
      } else if (errors > 0 && errors == _reports!.length) {
        icon = Icons.cloud_off;
        color = Colors.red;
        title = 'No se pudo conectar con la nube';
        lines.add('Revisa la conexión y vuelve a comprobar.');
      } else if (pending > 0) {
        icon = Icons.sync_problem;
        color = Colors.orange;
        title = pending == 1
            ? 'Hay 1 cambio por sincronizar'
            : 'Hay $pending cambios por sincronizar';
      } else if (errors > 0) {
        icon = Icons.warning_amber_rounded;
        color = Colors.orange;
        title = 'Lo comprobado está sincronizado';
      } else {
        icon = Icons.cloud_done;
        color = Colors.green;
        title = 'Todo está sincronizado';
      }

      if (!_busy) {
        if (errors > 0 && errors < _reports!.length) {
          lines.add(
            errors == 1
                ? '1 apartado no se pudo comprobar.'
                : '$errors apartados no se pudieron comprobar.',
          );
        }
        if (_checkedAt != null) {
          lines.add('Comprobado a las ${_hhmm(_checkedAt!)}');
        }
      }
    }

    final last = _lastResult;
    if (last != null && !_busy) {
      lines.add(
        last.failed == 0
            ? 'Última sincronización: ${last.done} '
                  '${last.done == 1 ? 'cambio aplicado' : 'cambios aplicados'}'
            : 'Última sincronización: ${last.done} aplicados, '
                  '${last.failed} con error',
      );
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      color: color.withAlpha(28),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: color.withAlpha(90)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 34),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  for (final l in lines)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(l, style: theme.textTheme.bodySmall),
                    ),
                  if (_lastResult != null &&
                      _lastResult!.errors.isNotEmpty &&
                      !_busy)
                    for (final e in _lastResult!.errors)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          '• $e',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.red.shade400,
                          ),
                        ),
                      ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Tarjeta por módulo ─────────────────────────────────────────────────────

  Widget _moduleCard(SyncModuleReport r) {
    final theme = Theme.of(context);

    final IconData statusIcon;
    final Color statusColor;
    final String subtitle;

    if (r.hasError) {
      statusIcon = Icons.cloud_off;
      statusColor = Colors.red;
      subtitle = r.error!;
    } else if (r.info != null) {
      statusIcon = Icons.info_outline;
      statusColor = Colors.green;
      subtitle = r.info!;
    } else if (r.items.isEmpty) {
      statusIcon = Icons.check_circle;
      statusColor = Colors.green;
      subtitle = r.total == 0
          ? 'Sin datos'
          : r.total == 1
          ? '1 elemento sincronizado'
          : '${r.total} elementos sincronizados';
    } else {
      statusIcon = Icons.sync_problem;
      statusColor = Colors.orange;
      subtitle = _countsText(r);
    }

    final leading = CircleAvatar(
      radius: 20,
      backgroundColor: theme.colorScheme.primary.withAlpha(30),
      child: Icon(r.icon, color: theme.colorScheme.primary, size: 22),
    );
    final title = Text(
      r.label,
      style: const TextStyle(fontWeight: FontWeight.w600),
    );
    final sub = Text(
      subtitle,
      style: theme.textTheme.bodySmall?.copyWith(
        color: r.hasError ? Colors.red.shade400 : null,
      ),
    );
    final status = Icon(statusIcon, color: statusColor);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: r.items.isEmpty
          ? ListTile(
              leading: leading,
              title: title,
              subtitle: sub,
              trailing: status,
            )
          : Theme(
              // Quita las líneas que ExpansionTile dibuja al abrirse.
              data: theme.copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                leading: leading,
                title: title,
                subtitle: sub,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [status, const Icon(Icons.expand_more)],
                ),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final a in _order)
                    if (r.count(a) > 0) ..._itemGroup(r, a),
                ],
              ),
            ),
    );
  }

  List<Widget> _itemGroup(SyncModuleReport r, SyncAction a) {
    final theme = Theme.of(context);
    final m = _meta(a);
    final items = r.items.where((i) => i.action == a).toList();
    final shown = items.take(_maxItemsShown);
    final rest = items.length - shown.length;

    return [
      Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 4),
        child: Row(
          children: [
            Icon(m.icon, size: 18, color: m.color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${m.header} (${items.length})',
                style: theme.textTheme.labelLarge?.copyWith(color: m.color),
              ),
            ),
          ],
        ),
      ),
      for (final i in shown)
        Padding(
          padding: const EdgeInsets.only(left: 26, top: 2, bottom: 2),
          child: Text(
            i.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium,
          ),
        ),
      if (rest > 0)
        Padding(
          padding: const EdgeInsets.only(left: 26, top: 2),
          child: Text(
            'y $rest más…',
            style: theme.textTheme.bodySmall?.copyWith(
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
    ];
  }

  // ── Cómo funciona ──────────────────────────────────────────────────────────

  Widget _rulesCard() {
    final theme = Theme.of(context);
    const rules = [
      'Lo que es tuyo y solo está en el móvil se sube a la nube.',
      'Lo que está en la nube y falta en el móvil se baja (salvo lo '
          'compartido que ocultaste).',
      'Si algo es distinto en los dos sitios, manda la nube, salvo que el '
          'móvil tenga cambios sin subir: entonces se sube lo del móvil.',
      'Lo que te compartieron y ya no te comparten se quita del móvil.',
      'Si un día del diario está escrito en los dos sitios con textos '
          'distintos, se juntan los dos: no se pierde nada.',
      'Nunca se borra nada de la nube.',
    ];
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      elevation: 0,
      color: theme.colorScheme.primary.withAlpha(14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.help_outline,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text('Cómo se sincroniza', style: theme.textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 8),
            for (final r in rules)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('•  '),
                    Expanded(child: Text(r, style: theme.textTheme.bodySmall)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ActionMeta {
  final IconData icon;
  final Color color;
  final String arrow;
  final String short;
  final String header;
  final String singular;
  final String plural;

  const _ActionMeta({
    required this.icon,
    required this.color,
    required this.arrow,
    required this.short,
    required this.header,
    required this.singular,
    required this.plural,
  });

  String verbPlural(int n) => n == 1 ? singular : plural;
}
