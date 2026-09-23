// lib/views/qr_share_screen.dart
//
// Pantalla de compartir perfil por QR.
// - "Mi QR"      → muestra el QR con uid/email/name del usuario actual.
// - "Escanear QR"→ abre la cámara, lee el QR de otro usuario y envía
//                  automáticamente una solicitud de amistad.

import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../core/friend_request_repository.dart';
import '../core/friend_repository.dart';

class QrShareScreen extends StatefulWidget {
  const QrShareScreen({Key? key}) : super(key: key);

  @override
  State<QrShareScreen> createState() => _QrShareScreenState();
}

class _QrShareScreenState extends State<QrShareScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Compartir por QR'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(icon: Icon(Icons.qr_code), text: 'Mi QR'),
            Tab(icon: Icon(Icons.qr_code_scanner), text: 'Escanear'),
          ],
        ),
      ),
      // physics: sin deslizar lateralmente, para que el gesto no se confunda
      // con mover la cámara al apuntar al QR.
      body: TabBarView(
        controller: _tabs,
        physics: const NeverScrollableScrollPhysics(),
        children: const [_MyQrTab(), _ScanQrTab()],
      ),
    );
  }
}

// ── Tab 1: Mi QR ──────────────────────────────────────────────────────────────

class _MyQrTab extends StatelessWidget {
  const _MyQrTab({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Center(child: Text('No hay sesión activa'));
    }

    final name = user.displayName ?? user.email?.split('@').first ?? 'Usuario';
    final email = (user.email ?? '').toLowerCase();

    // Payload del QR — JSON mínimo que identifica al usuario en la app
    final payload = jsonEncode({
      'app': 'NornApp',
      'uid': user.uid,
      'email': email,
      'name': name,
    });

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 16),
          Text(
            'Hola, $name',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            email,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 28),

          // QR
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.10),
                  blurRadius: 20,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            padding: const EdgeInsets.all(20),
            child: QrImageView(
              data: payload,
              version: QrVersions.auto,
              size: 240,
              backgroundColor: Colors.white,
              eyeStyle: const QrEyeStyle(
                eyeShape: QrEyeShape.square,
                color: Colors.black,
              ),
              dataModuleStyle: const QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square,
                color: Colors.black,
              ),
            ),
          ),
          const SizedBox(height: 24),

          Text(
            'Muestra este QR a un amigo para que te añada',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 16),

          // Copiar UID
          OutlinedButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: user.uid));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('UID copiado al portapapeles')),
              );
            },
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('Copiar mi ID'),
          ),
        ],
      ),
    );
  }
}

// ── Tab 2: Escanear QR ────────────────────────────────────────────────────────

class _ScanQrTab extends StatefulWidget {
  const _ScanQrTab({Key? key}) : super(key: key);

  @override
  State<_ScanQrTab> createState() => _ScanQrTabState();
}

class _ScanQrTabState extends State<_ScanQrTab> {
  bool _processing = false;
  bool _done = false;

  // Tras un QR no válido se ignoran lecturas durante un momento; si no, la
  // cámara lo vuelve a leer 4 veces por segundo y se llenaba de avisos.
  String? _lastRaw;
  DateTime _ignoreUntil = DateTime.fromMillisecondsSinceEpoch(0);

  final MobileScannerController _cam = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.normal,
  );

  @override
  void dispose() {
    _cam.dispose();
    super.dispose();
  }

  /// Interpreta el contenido del QR (JSON generado en "Mi QR").
  Map<String, dynamic>? _parsePayload(String raw) {
    final text = raw.trim();
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map) {
        final data = Map<String, dynamic>.from(decoded);
        // ⚠️ ANTES: se comparaba con 'nornapp' pero el QR se genera con
        // 'NornApp' → NUNCA coincidía y todos los QR daban error.
        final app = (data['app'] ?? '').toString().toLowerCase();
        if (app != 'nornapp') return null;
        return data;
      }
    } catch (_) {
      // No es JSON → no es un QR de NornApp.
    }
    return null;
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_processing || _done) return;
    if (capture.barcodes.isEmpty) return;

    String? raw;
    for (final b in capture.barcodes) {
      final v = b.rawValue;
      if (v != null && v.trim().isNotEmpty) {
        raw = v;
        break;
      }
    }
    if (raw == null) return;

    // Mismo QR leído justo después de un error → se ignora un rato.
    if (raw == _lastRaw && DateTime.now().isBefore(_ignoreUntil)) return;
    _lastRaw = raw;

    setState(() => _processing = true);

    try {
      final data = _parsePayload(raw);
      if (data == null) {
        _showError('Este QR no pertenece a NornApp');
        return;
      }

      final toUid = (data['uid'] ?? '').toString();
      final toEmail = (data['email'] ?? '').toString();
      final rawName = (data['name'] ?? '').toString();
      final toName = rawName.isNotEmpty
          ? rawName
          : (toEmail.isNotEmpty ? toEmail : 'tu amigo');

      if (toUid.isEmpty) {
        _showError('QR inválido — falta el identificador');
        return;
      }

      // Evitar escanearse a uno mismo
      final myUid = FirebaseAuth.instance.currentUser?.uid;
      if (myUid == toUid) {
        _showError('No puedes añadirte a ti mismo 😄');
        return;
      }

      // Verificar si ya son amigos
      final friends = await FriendRepository.instance.getAll();
      if (friends.any((f) => f.firebaseUid == toUid)) {
        _showInfo('Ya sois amigos');
        return;
      }

      // Enviar solicitud de amistad
      final result = await FriendRequestRepository.instance.sendRequest(
        toUid: toUid,
        toEmail: toEmail,
        fromLogo: '😊', // logo por defecto; el receptor puede cambiarlo
      );

      if (!mounted) return;

      switch (result) {
        case null:
          _showError('No hay sesión activa');
          break;
        case 'already_sent':
          _showInfo('Ya le enviaste una solicitud a $toName');
          break;
        case 'already_friends':
          _showInfo('Ya sois amigos');
          break;
        case 'self':
          _showError('No puedes añadirte a ti mismo');
          break;
        default:
          // Éxito
          setState(() => _done = true);
          await _cam.stop();
          _showSuccess(toName);
      }
    } catch (e) {
      debugPrint('❌ Error procesando QR: $e');
      _showError('No se pudo enviar la solicitud. Revisa tu conexión.');
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  void _pauseRepeats() {
    _ignoreUntil = DateTime.now().add(const Duration(seconds: 3));
  }

  void _showError(String msg) {
    _pauseRepeats();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.red.shade600),
      );
  }

  void _showInfo(String msg) {
    _pauseRepeats();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  void _showSuccess(String name) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('✅ Solicitud enviada'),
        content: Text(
          'Se envió una solicitud de amistad a $name.\n'
          'Cuando la acepte aparecerá en tu lista de amigos.',
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.of(dialogCtx).pop(); // cierra el diálogo
              Navigator.of(context).maybePop(); // vuelve al menú
            },
            child: const Text('Genial'),
          ),
        ],
      ),
    );
  }

  Widget _buildCameraError(MobileScannerException error) {
    final denied = error.errorCode == MobileScannerErrorCode.permissionDenied;
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.all(24),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            denied ? Icons.no_photography_outlined : Icons.error_outline,
            color: Colors.white,
            size: 56,
          ),
          const SizedBox(height: 16),
          Text(
            denied
                ? 'NornApp no tiene permiso para usar la cámara.\n'
                      'Actívalo en Ajustes del teléfono → NornApp → Cámara.'
                : 'No se pudo iniciar la cámara (${error.errorCode.name}).',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
            onPressed: () async {
              try {
                await _cam.start();
              } catch (_) {}
            },
            child: const Text('Reintentar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_done) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, color: Colors.green, size: 80),
            SizedBox(height: 16),
            Text(
              '¡Solicitud enviada!',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      );
    }

    return Stack(
      children: [
        // Cámara
        Positioned.fill(
          child: MobileScanner(
            controller: _cam,
            onDetect: _onDetect,
            errorBuilder: (context, error, child) => _buildCameraError(error),
          ),
        ),

        // Marco de escaneo
        Center(
          child: IgnorePointer(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 3),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ),

        // Linterna
        Positioned(
          top: 16,
          right: 16,
          child: CircleAvatar(
            backgroundColor: Colors.black54,
            child: IconButton(
              tooltip: 'Linterna',
              icon: const Icon(Icons.flash_on, color: Colors.white),
              onPressed: () => _cam.toggleTorch(),
            ),
          ),
        ),

        // Instrucción
        Positioned(
          bottom: 48,
          left: 0,
          right: 0,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 32),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.6),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              'Apunta la cámara al QR de tu amigo',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 14),
            ),
          ),
        ),

        // Indicador de procesando
        if (_processing)
          Positioned.fill(
            child: Container(
              color: Colors.black.withOpacity(0.5),
              child: const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),
          ),
      ],
    );
  }
}
