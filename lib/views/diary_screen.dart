// lib/views/diary_screen.dart

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// ── Punto de entrada: comprueba PIN antes de mostrar el diario ───────────────

class DiaryScreen extends StatelessWidget {
  const DiaryScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return const _PinGate();
  }
}

// ── Gate de PIN ───────────────────────────────────────────────────────────────

class _PinGate extends StatefulWidget {
  const _PinGate({Key? key}) : super(key: key);
  @override
  State<_PinGate> createState() => _PinGateState();
}

class _PinGateState extends State<_PinGate> {
  static const _pinKey = 'diary_pin';

  bool _unlocked = false;
  bool _loading = true;
  bool _isNew = false; // primera vez → crear PIN
  String _storedPin = '';
  String _entered = '';
  String _firstEntry = ''; // para confirmación en registro
  bool _confirming = false; // fase 2 del registro
  String? _error;

  @override
  void initState() {
    super.initState();
    _checkPin();
  }

  Future<void> _checkPin() async {
    final prefs = await SharedPreferences.getInstance();
    final pin = prefs.getString(_pinKey) ?? '';
    if (mounted)
      setState(() {
        _storedPin = pin;
        _isNew = pin.isEmpty;
        _loading = false;
      });
  }

  void _onDigit(String d) {
    if (_entered.length >= 4) return;
    setState(() {
      _entered += d;
      _error = null;
    });
    if (_entered.length == 4) _verify();
  }

  void _onDelete() {
    if (_entered.isEmpty) return;
    setState(() => _entered = _entered.substring(0, _entered.length - 1));
  }

  Future<void> _verify() async {
    if (_isNew) {
      // ── Crear PIN ──────────────────────────────────────────────────────────
      if (!_confirming) {
        setState(() {
          _firstEntry = _entered;
          _entered = '';
          _confirming = true;
        });
      } else {
        if (_entered == _firstEntry) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_pinKey, _entered);
          if (mounted) setState(() => _unlocked = true);
        } else {
          setState(() {
            _error = 'Los PINs no coinciden. Inténtalo de nuevo.';
            _entered = '';
            _confirming = false;
            _firstEntry = '';
          });
        }
      }
    } else {
      // ── Verificar PIN ──────────────────────────────────────────────────────
      if (_entered == _storedPin) {
        setState(() => _unlocked = true);
      } else {
        setState(() {
          _error = 'PIN incorrecto';
          _entered = '';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Color(0xFFF5ECD7),
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_unlocked) return const _DiaryContent();
    return _PinScreen(
      isNew: _isNew,
      confirming: _confirming,
      entered: _entered,
      error: _error,
      onDigit: _onDigit,
      onDelete: _onDelete,
    );
  }
}

// ── Pantalla de PIN ───────────────────────────────────────────────────────────

class _PinScreen extends StatelessWidget {
  final bool isNew;
  final bool confirming;
  final String entered;
  final String? error;
  final void Function(String) onDigit;
  final VoidCallback onDelete;

  const _PinScreen({
    required this.isNew,
    required this.confirming,
    required this.entered,
    required this.error,
    required this.onDigit,
    required this.onDelete,
    Key? key,
  }) : super(key: key);

  String get _title {
    if (!isNew) return 'Introduce tu PIN';
    if (!confirming) return 'Crea un PIN para tu diario';
    return 'Confirma el PIN';
  }

  String get _subtitle {
    if (!isNew) return 'Tu diario está protegido';
    if (!confirming) return 'Elige 4 dígitos que recuerdes';
    return 'Vuelve a introducir el PIN';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5ECD7),
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 32),
            // Icono
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: const Color(0xFF7B6FAB).withOpacity(0.12),
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(0xFF7B6FAB).withOpacity(0.3),
                  width: 2,
                ),
              ),
              child: const Icon(
                Icons.menu_book_outlined,
                size: 38,
                color: Color(0xFF7B6FAB),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              _title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Color(0xFF4A3728),
                fontFamily: 'serif',
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _subtitle,
              style: TextStyle(fontSize: 13, color: Colors.brown.shade400),
            ),
            const SizedBox(height: 32),

            // Indicadores de dígitos
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(4, (i) {
                final filled = i < entered.length;
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 10),
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: filled
                        ? const Color(0xFF7B6FAB)
                        : Colors.transparent,
                    border: Border.all(
                      color: const Color(0xFF7B6FAB),
                      width: 2,
                    ),
                  ),
                );
              }),
            ),

            // Error
            if (error != null) ...[
              const SizedBox(height: 12),
              Text(
                error!,
                style: const TextStyle(color: Colors.red, fontSize: 13),
              ),
            ],

            const SizedBox(height: 40),

            // Teclado numérico
            _NumPad(onDigit: onDigit, onDelete: onDelete),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

// ── Teclado numérico ──────────────────────────────────────────────────────────

class _NumPad extends StatelessWidget {
  final void Function(String) onDigit;
  final VoidCallback onDelete;

  const _NumPad({required this.onDigit, required this.onDelete, Key? key})
    : super(key: key);

  @override
  Widget build(BuildContext context) {
    final keys = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['', '0', 'del'],
    ];
    return Column(
      children: keys
          .map(
            (row) => Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: row.map((k) {
                if (k.isEmpty) return const SizedBox(width: 80, height: 72);
                return _NumKey(
                  label: k,
                  onPressed: k == 'del' ? onDelete : () => onDigit(k),
                  isDelete: k == 'del',
                );
              }).toList(),
            ),
          )
          .toList(),
    );
  }
}

class _NumKey extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  final bool isDelete;

  const _NumKey({
    required this.label,
    required this.onPressed,
    this.isDelete = false,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 80,
      height: 72,
      child: InkWell(
        borderRadius: BorderRadius.circular(40),
        onTap: onPressed,
        child: Center(
          child: isDelete
              ? const Icon(
                  Icons.backspace_outlined,
                  color: Color(0xFF7B6FAB),
                  size: 22,
                )
              : Text(
                  label,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF4A3728),
                  ),
                ),
        ),
      ),
    );
  }
}

// ── Contenido real del diario (renombrado) ────────────────────────────────────

class _DiaryContent extends StatefulWidget {
  const _DiaryContent({Key? key}) : super(key: key);
  @override
  State<_DiaryContent> createState() => _DiaryContentState();
}

class _DiaryContentState extends State<_DiaryContent>
    with SingleTickerProviderStateMixin {
  DateTime _currentDay = DateTime.now();
  final TextEditingController _ctrl = TextEditingController();
  late AnimationController _pageAnim;
  late Animation<double> _fadeAnim;
  bool _saving = false;
  bool _forward = true; // dirección del flip

  // Clave única por día en SharedPreferences
  String _key(DateTime d) =>
      'diary_${d.year}_${d.month.toString().padLeft(2, '0')}_${d.day.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    _pageAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _fadeAnim = Tween<double>(
      begin: 1,
      end: 0,
    ).animate(CurvedAnimation(parent: _pageAnim, curve: Curves.easeIn));
    _loadEntry(_currentDay);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _pageAnim.dispose();
    super.dispose();
  }

  // ── Persistencia ───────────────────────────────────────────────────────────

  Future<void> _loadEntry(DateTime day) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(day)) ?? '';
    if (mounted) _ctrl.text = raw;
  }

  Future<void> _saveEntry() async {
    setState(() => _saving = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(_currentDay), _ctrl.text);
    if (mounted) setState(() => _saving = false);
  }

  // ── Navegación entre días ──────────────────────────────────────────────────

  Future<void> _goTo(DateTime next, {required bool forward}) async {
    setState(() => _forward = forward);
    await _saveEntry();
    // Flip-out
    await _pageAnim.forward();
    await _loadEntry(next);
    if (mounted) setState(() => _currentDay = next);
    // Flip-in
    await _pageAnim.reverse();
  }

  void _prevDay() =>
      _goTo(_currentDay.subtract(const Duration(days: 1)), forward: false);

  void _nextDay() {
    final tomorrow = _currentDay.add(const Duration(days: 1));
    if (tomorrow.isAfter(DateTime.now())) return; // no diario futuro
    _goTo(tomorrow, forward: true);
  }

  bool get _isToday {
    final now = DateTime.now();
    return _currentDay.year == now.year &&
        _currentDay.month == now.month &&
        _currentDay.day == now.day;
  }

  // ── Selector de fecha (calendario) ────────────────────────────────────────

  Future<void> _openCalendar() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _currentDay,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: ColorScheme.light(
            primary: const Color(0xFF7B6FAB),
            onPrimary: Colors.white,
            surface: const Color(0xFFFDF8F2),
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null && picked != _currentDay) {
      _goTo(picked, forward: picked.isAfter(_currentDay));
    }
  }

  // ── Formato de fecha ───────────────────────────────────────────────────────

  static const _dias = [
    '',
    'Lunes',
    'Martes',
    'Miércoles',
    'Jueves',
    'Viernes',
    'Sábado',
    'Domingo',
  ];
  static const _meses = [
    '',
    'enero',
    'febrero',
    'marzo',
    'abril',
    'mayo',
    'junio',
    'julio',
    'agosto',
    'septiembre',
    'octubre',
    'noviembre',
    'diciembre',
  ];

  String get _dateLabel {
    final d = _currentDay;
    return '${_dias[d.weekday]}, ${d.day} de ${_meses[d.month]} de ${d.year}';
  }

  // ── Subir / bajar copia ───────────────────────────────────────────────────

  /// Sube TODAS las entradas del diario a Firestore bajo
  /// users/{uid}/diary/{YYYY_MM_DD} = { text: '...' }
  Future<void> _uploadBackup() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await _saveEntry(); // guardar la actual antes de subir
    setState(() => _saving = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs
          .getKeys()
          .where((k) => k.startsWith('diary_'))
          .toList();
      if (keys.isEmpty) {
        _showSnack('No hay entradas para subir', error: false);
        return;
      }
      final col = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('diary');
      final batch = FirebaseFirestore.instance.batch();
      for (final k in keys) {
        final dayKey = k.replaceFirst('diary_', '');
        batch.set(col.doc(dayKey), {'text': prefs.getString(k) ?? ''});
      }
      await batch.commit();
      _showSnack('✅ ${keys.length} entradas subidas correctamente');
    } catch (e) {
      _showSnack('Error al subir: \$e', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Descarga todas las entradas desde Firestore a SharedPreferences local.
  Future<void> _downloadBackup() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    setState(() => _saving = true);
    try {
      final col = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('diary');
      final snap = await col.get();
      if (snap.docs.isEmpty) {
        _showSnack('No hay copia en la nube', error: false);
        return;
      }
      final prefs = await SharedPreferences.getInstance();
      for (final doc in snap.docs) {
        final text = doc.data()['text'] as String? ?? '';
        await prefs.setString('diary_\${doc.id}', text);
      }
      // Recargar la entrada del día actual
      await _loadEntry(_currentDay);
      if (mounted) setState(() {});
      _showSnack('✅ \${snap.docs.length} entradas descargadas');
    } catch (e) {
      _showSnack('Error al descargar: \$e', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showSnack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? Colors.red.shade600 : Colors.green.shade600,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  /// Muestra el diálogo informativo sobre almacenamiento local.
  void _showInfo() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.info_outline, color: Color(0xFF7B6FAB)),
            SizedBox(width: 8),
            Text('Sobre tu diario'),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('📱 Los textos se guardan localmente en tu dispositivo.'),
            SizedBox(height: 10),
            Text('❌ No requiere conexión a internet.'),
            SizedBox(height: 6),
            Text('❌ No se sincroniza automáticamente entre dispositivos.'),
            SizedBox(height: 6),
            Text(
              '❌ Si cambias de móvil o reinstalaas la app, los textos se pierden.',
            ),
            SizedBox(height: 14),
            Text(
              '💡 Para traspasar a otro dispositivo:',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 6),
            Text('1. En este móvil pulsa ☁️ Subir copia.'),
            Text(
              '2. En el nuevo dispositivo inicia sesión y pulsa ⬇️ Bajar copia.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5ECD7), // pergamino
      appBar: AppBar(
        backgroundColor: const Color(0xFF7B6FAB),
        foregroundColor: Colors.white,
        title: const Text('Mi Diario'),
        elevation: 0,
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              ),
            )
          else ...[
            IconButton(
              icon: const Icon(Icons.info_outline),
              tooltip: 'Información',
              onPressed: _showInfo,
            ),
            IconButton(
              icon: const Icon(Icons.cloud_upload_outlined),
              tooltip: 'Subir copia a la nube',
              onPressed: _uploadBackup,
            ),
            IconButton(
              icon: const Icon(Icons.cloud_download_outlined),
              tooltip: 'Bajar copia de la nube',
              onPressed: _downloadBackup,
            ),
            IconButton(
              icon: const Icon(Icons.save_outlined),
              tooltip: 'Guardar',
              onPressed: _saveEntry,
            ),
          ],
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // ── Cabecera: flechas + fecha + calendario ─────────────────────
              Row(
                children: [
                  // Flecha anterior
                  _NavArrow(icon: Icons.chevron_left, onPressed: _prevDay),
                  const SizedBox(width: 8),

                  // Fecha centrada
                  Expanded(
                    child: GestureDetector(
                      onTap: _openCalendar,
                      child: Column(
                        children: [
                          if (_isToday)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 2,
                              ),
                              margin: const EdgeInsets.only(bottom: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFF7B6FAB),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Text(
                                'Hoy',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          Text(
                            _dateLabel,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF4A3728),
                              fontFamily: 'serif',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(width: 8),

                  // Botón calendario
                  Tooltip(
                    message: 'Elegir fecha',
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: _openCalendar,
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Icon(
                          Icons.calendar_month_outlined,
                          size: 22,
                          color: const Color(0xFF7B6FAB),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(width: 4),

                  // Flecha siguiente
                  _NavArrow(
                    icon: Icons.chevron_right,
                    onPressed: _isToday ? null : _nextDay,
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // ── Página de diario ──────────────────────────────────────────
              Expanded(
                child: FadeTransition(
                  opacity: _fadeAnim,
                  child: _BookPage(
                    day: _currentDay,
                    controller: _ctrl,
                    onChanged: (_) {}, // autoguardado al cambiar de día
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Página estilo libro ────────────────────────────────────────────────────────

class _BookPage extends StatelessWidget {
  final DateTime day;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  const _BookPage({
    required this.day,
    required this.controller,
    required this.onChanged,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFDF8F0),
        borderRadius: BorderRadius.circular(4),
        boxShadow: [
          BoxShadow(
            color: Colors.brown.withOpacity(0.18),
            blurRadius: 12,
            offset: const Offset(4, 6),
          ),
          BoxShadow(
            color: Colors.brown.withOpacity(0.08),
            blurRadius: 4,
            offset: const Offset(-2, -2),
          ),
        ],
      ),
      child: Stack(
        children: [
          // ── Encuadernación izquierda ──────────────────────────────────────
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Container(
              width: 28,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    const Color(0xFF7B6FAB).withOpacity(0.85),
                    const Color(0xFF7B6FAB).withOpacity(0.3),
                    Colors.transparent,
                  ],
                ),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(4),
                  bottomLeft: Radius.circular(4),
                ),
              ),
            ),
          ),

          // ── Líneas horizontales (renglones) ───────────────────────────────
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(36, 20, 16, 16),
              child: CustomPaint(painter: _LinePainter()),
            ),
          ),

          // ── Área de texto ─────────────────────────────────────────────────
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(38, 16, 16, 16),
              child: TextField(
                controller: controller,
                onChanged: onChanged,
                maxLines: null,
                expands: true,
                keyboardType: TextInputType.multiline,
                style: const TextStyle(
                  fontSize: 15,
                  height: 2.05, // alineado con los renglones (28px / 2.05 ≈ 14)
                  color: Color(0xFF2C1E0E),
                  fontFamily: 'serif',
                ),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  hintText: '¿Qué ha pasado hoy?',
                  hintStyle: TextStyle(
                    color: Color(0xFFB0956A),
                    fontStyle: FontStyle.italic,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
          ),

          // ── Número de página (decorativo) ─────────────────────────────────
          Positioned(
            right: 12,
            bottom: 8,
            child: Text(
              '${day.day}',
              style: TextStyle(
                fontSize: 11,
                color: const Color(0xFF7B6FAB).withOpacity(0.4),
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Painter de renglones ───────────────────────────────────────────────────────

class _LinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFD4B896).withOpacity(0.5)
      ..strokeWidth = 0.8;

    const lineHeight = 29.0; // altura de cada renglón
    var y = lineHeight;
    while (y < size.height) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
      y += lineHeight;
    }
  }

  @override
  bool shouldRepaint(_) => false;
}

// ── Flecha de navegación ───────────────────────────────────────────────────────

class _NavArrow extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;

  const _NavArrow({required this.icon, this.onPressed, Key? key})
    : super(key: key);

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Material(
      color: const Color(0xFF7B6FAB).withOpacity(enabled ? 0.15 : 0.05),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(
            icon,
            size: 24,
            color: enabled
                ? const Color(0xFF7B6FAB)
                : const Color(0xFF7B6FAB).withOpacity(0.3),
          ),
        ),
      ),
    );
  }
}
