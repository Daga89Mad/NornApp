// lib/views/shopping_list_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/weekly_menu_model.dart';
import '../core/weekly_menu_repository.dart';

// ── Meses en español ─────────────────────────────────────────────────────────
const _mesesLargos = [
  '',
  'Enero',
  'Febrero',
  'Marzo',
  'Abril',
  'Mayo',
  'Junio',
  'Julio',
  'Agosto',
  'Septiembre',
  'Octubre',
  'Noviembre',
  'Diciembre',
];

/// Pantalla que agrega todos los ingredientes de los menús del mes en una
/// lista de la compra. Los menús se guardan como texto libre, así que los
/// ingredientes se extraen troceando por comas y detectando cantidades.
class ShoppingListScreen extends StatefulWidget {
  /// Cualquier día dentro del mes que se quiere mostrar.
  final DateTime initialMonth;

  const ShoppingListScreen({Key? key, required this.initialMonth})
    : super(key: key);

  @override
  State<ShoppingListScreen> createState() => _ShoppingListScreenState();
}

class _ShoppingListScreenState extends State<ShoppingListScreen> {
  final _repo = WeeklyMenuRepository.instance;

  static const Color _primary = Color(0xFF5C6BC0);

  late DateTime _month; // primer día del mes mostrado
  List<_ShoppingItem> _items = [];
  final Set<String> _checked = {}; // claves marcadas (en memoria)
  bool _isLoading = true;
  bool _includeNotes = false;

  @override
  void initState() {
    super.initState();
    _month = DateTime(widget.initialMonth.year, widget.initialMonth.month, 1);
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final entries = await _repo.getEntriesForMonth(_month);
    final items = _buildShoppingList(entries, includeNotes: _includeNotes);
    setState(() {
      _items = items;
      _isLoading = false;
    });
  }

  void _prevMonth() {
    setState(() => _month = DateTime(_month.year, _month.month - 1, 1));
    _checked.clear();
    _load();
  }

  void _nextMonth() {
    setState(() => _month = DateTime(_month.year, _month.month + 1, 1));
    _checked.clear();
    _load();
  }

  String get _monthLabel => '${_mesesLargos[_month.month]} ${_month.year}';

  // ── Copiar la lista al portapapeles (útil para pegar en WhatsApp) ──────────
  Future<void> _copyList() async {
    if (_items.isEmpty) return;
    final buffer = StringBuffer();
    buffer.writeln('🛒 Lista de la compra — $_monthLabel');
    buffer.writeln('');
    for (final item in _items) {
      final done = _checked.contains(item.key);
      final mark = done ? '✅' : '▫️';
      final qty = item.quantityLabel.isNotEmpty
          ? ' — ${item.quantityLabel}'
          : '';
      buffer.writeln('$mark ${item.displayName}$qty');
    }
    await Clipboard.setData(ClipboardData(text: buffer.toString()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Lista copiada al portapapeles')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pending = _items.where((i) => !_checked.contains(i.key)).length;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: _primary,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Lista de la compra'),
        actions: [
          IconButton(
            tooltip: 'Copiar lista',
            icon: const Icon(Icons.copy_all),
            onPressed: _items.isEmpty ? null : _copyList,
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'notas') {
                setState(() => _includeNotes = !_includeNotes);
                _load();
              } else if (v == 'limpiar') {
                setState(() => _checked.clear());
              }
            },
            itemBuilder: (_) => [
              CheckedPopupMenuItem(
                value: 'notas',
                checked: _includeNotes,
                child: const Text('Incluir notas'),
              ),
              const PopupMenuItem(
                value: 'limpiar',
                child: Text('Desmarcar todo'),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          _buildMonthBar(pending),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _items.isEmpty
                ? _buildEmpty()
                : _buildList(),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthBar(int pending) {
    return Container(
      color: _primary,
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left, color: Colors.white),
            onPressed: _prevMonth,
            tooltip: 'Mes anterior',
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  _monthLabel,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                Container(
                  margin: const EdgeInsets.only(top: 2),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _items.isEmpty
                        ? 'Sin artículos'
                        : '$pending por comprar · ${_items.length} en total',
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right, color: Colors.white),
            onPressed: _nextMonth,
            tooltip: 'Mes siguiente',
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.shopping_cart_outlined,
            size: 64,
            color: Colors.grey.shade300,
          ),
          const SizedBox(height: 12),
          Text(
            'No hay menús en $_monthLabel',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 15),
          ),
          const SizedBox(height: 4),
          Text(
            'Añade platos al menú y aparecerán aquí.',
            style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    // Pendientes arriba, marcados abajo.
    final pending = _items.where((i) => !_checked.contains(i.key)).toList();
    final done = _items.where((i) => _checked.contains(i.key)).toList();
    final ordered = [...pending, ...done];

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
      itemCount: ordered.length,
      separatorBuilder: (_, __) => const SizedBox(height: 4),
      itemBuilder: (_, i) {
        final item = ordered[i];
        final isChecked = _checked.contains(item.key);
        return Card(
          margin: EdgeInsets.zero,
          elevation: isChecked ? 0 : 1,
          color: isChecked ? Colors.grey.shade100 : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          child: CheckboxListTile(
            controlAffinity: ListTileControlAffinity.leading,
            activeColor: _primary,
            value: isChecked,
            onChanged: (v) {
              setState(() {
                if (v == true) {
                  _checked.add(item.key);
                } else {
                  _checked.remove(item.key);
                }
              });
            },
            title: Text(
              item.displayName,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14.5,
                decoration: isChecked ? TextDecoration.lineThrough : null,
                color: isChecked ? Colors.grey : null,
              ),
            ),
            subtitle: item.quantityLabel.isEmpty
                ? null
                : Text(
                    item.quantityLabel,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: isChecked ? Colors.grey.shade400 : _primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
            secondary: item.occurrences > 1
                ? Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: _primary.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '×${item.occurrences}',
                      style: TextStyle(
                        fontSize: 11,
                        color: _primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  )
                : null,
          ),
        );
      },
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // PARSEO Y AGREGACIÓN DE INGREDIENTES
  // ══════════════════════════════════════════════════════════════════════════

  List<_ShoppingItem> _buildShoppingList(
    List<WeeklyMenuEntry> entries, {
    bool includeNotes = false,
  }) {
    final map = <String, _Aggregate>{};

    for (final e in entries) {
      final sources = <String>[e.title];
      if (includeNotes && e.description.trim().isNotEmpty) {
        sources.add(e.description);
      }
      for (final src in sources) {
        for (final piece in _splitOutsideParens(src)) {
          final parsed = _parsePiece(piece);
          if (parsed == null) continue;
          final agg = map.putIfAbsent(
            parsed.key,
            () => _Aggregate(display: parsed.display),
          );
          agg.occurrences += 1;
          if (parsed.amount != null && parsed.unit != null) {
            agg.byUnit.update(
              parsed.unit!,
              (v) => v + parsed.amount!,
              ifAbsent: () => parsed.amount!,
            );
          }
        }
      }
    }

    final items = map.entries.map((entry) {
      return _ShoppingItem(
        key: entry.key,
        displayName: entry.value.display,
        quantityLabel: _formatQuantities(entry.value.byUnit),
        occurrences: entry.value.occurrences,
      );
    }).toList();

    // Orden alfabético por nombre visible.
    items.sort(
      (a, b) => _stripAccents(
        a.displayName.toLowerCase(),
      ).compareTo(_stripAccents(b.displayName.toLowerCase())),
    );
    return items;
  }

  /// Trocea por comas que estén FUERA de paréntesis, para no romper
  /// "Café con leche (200 ml leche desnatada)".
  List<String> _splitOutsideParens(String input) {
    final result = <String>[];
    final buffer = StringBuffer();
    int depth = 0;
    for (final ch in input.split('')) {
      if (ch == '(' || ch == '[') depth++;
      if (ch == ')' || ch == ']') depth = depth > 0 ? depth - 1 : 0;
      if ((ch == ',' || ch == ';') && depth == 0) {
        result.add(buffer.toString());
        buffer.clear();
      } else {
        buffer.write(ch);
      }
    }
    if (buffer.isNotEmpty) result.add(buffer.toString());
    return result;
  }

  /// Extrae de un trozo el nombre y (si hay) una cantidad + unidad.
  _ParsedPiece? _parsePiece(String raw) {
    var piece = raw.trim();
    if (piece.isEmpty) return null;

    // Detectar cantidad: número (o fracción) + unidad opcional, en el trozo.
    // Ejemplos: "60 g", "200 ml", "1,5 kg", "½ cuch", "2 unidades".
    final qty = _extractAmount(piece);

    // Nombre "bonito": quitar paréntesis, cantidades y sobrantes.
    var name = piece.replaceAll(RegExp(r'\([^)]*\)'), ' ');
    name = name.replaceAll(
      RegExp(
        r'\d+([.,]\d+)?\s*(kg|g|gr|grs|ml|l|cl|uds?|unidad(es)?|cuch(aradas?)?|cda|cdta|pizca|puñado)?',
        caseSensitive: false,
      ),
      ' ',
    );
    name = name.replaceAll(RegExp(r'[½¼¾⅓⅔]'), ' ');
    name = name.replaceAll(RegExp(r'\s+'), ' ').trim();
    // Quitar conectores sobrantes al principio ("de ", "con ", "y ").
    name = name.replaceAll(
      RegExp(r'^(de|con|y|a|al|la|el|los|las)\s+', caseSensitive: false),
      '',
    );
    name = name.trim();

    if (name.isEmpty) {
      // Si no quedó nombre pero había texto, usar el trozo original limpio.
      name = piece.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (name.isEmpty) return null;
    }

    final display = _capitalize(name);
    final key = _normalizeKey(name);
    if (key.isEmpty) return null;

    return _ParsedPiece(
      key: key,
      display: display,
      amount: qty?.amount,
      unit: qty?.unit,
    );
  }

  _Amount? _extractAmount(String piece) {
    // Fracciones unicode → decimal.
    final fractions = {'½': 0.5, '¼': 0.25, '¾': 0.75, '⅓': 0.333, '⅔': 0.667};

    // Buscar patrón número + unidad.
    final re = RegExp(
      r'(\d+([.,]\d+)?)\s*(kg|g|gr|grs|ml|l|cl|uds?|unidad(?:es)?)?',
      caseSensitive: false,
    );
    for (final m in re.allMatches(piece)) {
      final numStr = m.group(1);
      if (numStr == null) continue;
      final value = double.tryParse(numStr.replaceAll(',', '.'));
      if (value == null) continue;
      final unitRaw = (m.group(3) ?? '').toLowerCase();
      final canon = _canonUnit(unitRaw);
      if (canon != null) {
        return _Amount(_toBase(value, unitRaw), canon);
      }
      // número sin unidad reconocida → contar como unidades
      return _Amount(value, 'ud');
    }

    // Fracciones tipo "½ cuch"
    for (final entry in fractions.entries) {
      if (piece.contains(entry.key)) {
        return _Amount(entry.value, 'ud');
      }
    }
    return null;
  }

  String? _canonUnit(String u) {
    switch (u) {
      case 'kg':
      case 'g':
      case 'gr':
      case 'grs':
        return 'g';
      case 'l':
      case 'cl':
      case 'ml':
        return 'ml';
      case 'ud':
      case 'uds':
      case 'unidad':
      case 'unidades':
        return 'ud';
      default:
        return null;
    }
  }

  /// Convierte el valor a la unidad base (g o ml) según la unidad escrita.
  double _toBase(double value, String unitRaw) {
    switch (unitRaw) {
      case 'kg':
        return value * 1000;
      case 'l':
        return value * 1000;
      case 'cl':
        return value * 10;
      default:
        return value; // g, gr, grs, ml, ud…
    }
  }

  String _formatQuantities(Map<String, double> byUnit) {
    if (byUnit.isEmpty) return '';
    final parts = <String>[];
    byUnit.forEach((unit, total) {
      switch (unit) {
        case 'g':
          if (total >= 1000) {
            parts.add('${_num(total / 1000)} kg');
          } else {
            parts.add('${_num(total)} g');
          }
          break;
        case 'ml':
          if (total >= 1000) {
            parts.add('${_num(total / 1000)} l');
          } else {
            parts.add('${_num(total)} ml');
          }
          break;
        case 'ud':
          parts.add('${_num(total)} ud');
          break;
        default:
          parts.add('${_num(total)} $unit');
      }
    });
    return parts.join(' + ');
  }

  String _num(double v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(1).replaceAll('.', ',');
  }

  String _normalizeKey(String name) {
    var k = _stripAccents(name.toLowerCase()).trim();
    k = k.replaceAll(RegExp(r'\s+'), ' ');
    // singular muy básico para agrupar plural/singular
    if (k.length > 4 && k.endsWith('s')) k = k.substring(0, k.length - 1);
    return k;
  }

  String _stripAccents(String s) {
    const from = 'áàäâãéèëêíìïîóòöôõúùüûñç';
    const to = 'aaaaaeeeeiiiiooooouuuunc';
    var out = s;
    for (int i = 0; i < from.length; i++) {
      out = out.replaceAll(from[i], to[i]);
    }
    return out;
  }

  String _capitalize(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1);
  }
}

// ── Estructuras auxiliares ───────────────────────────────────────────────────

class _ShoppingItem {
  final String key;
  final String displayName;
  final String quantityLabel;
  final int occurrences;

  _ShoppingItem({
    required this.key,
    required this.displayName,
    required this.quantityLabel,
    required this.occurrences,
  });
}

class _Aggregate {
  final String display;
  int occurrences = 0;
  final Map<String, double> byUnit = {};
  _Aggregate({required this.display});
}

class _ParsedPiece {
  final String key;
  final String display;
  final double? amount;
  final String? unit;
  _ParsedPiece({
    required this.key,
    required this.display,
    this.amount,
    this.unit,
  });
}

class _Amount {
  final double amount;
  final String unit;
  _Amount(this.amount, this.unit);
}
