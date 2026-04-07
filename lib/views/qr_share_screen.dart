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
      body: TabBarView(
        controller: _tabs,
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
      'app': 'familycalendar',
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
  final MobileScannerController _cam = MobileScannerController();

  @override
  void dispose() {
    _cam.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_processing || _done) return;
    final raw = capture.barcodes.first.rawValue;
    if (raw == null) return;

    setState(() => _processing = true);

    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;

      // Verificar que es un QR de nuestra app
      if (data['app'] != 'familycalendar') {
        _showError('Este QR no pertenece a FamilyCalendar');
        return;
      }

      final toUid = data['uid'] as String? ?? '';
      final toEmail = data['email'] as String? ?? '';
      final toName = data['name'] as String? ?? toEmail;

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
          _cam.stop();
          _showSuccess(toName);
      }
    } catch (e) {
      _showError('QR no reconocido');
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red.shade600),
    );
    setState(() {
      _processing = false;
    });
  }

  void _showInfo(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    setState(() {
      _processing = false;
    });
  }

  void _showSuccess(String name) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('✅ Solicitud enviada'),
        content: Text(
          'Se envió una solicitud de amistad a $name.\n'
          'Cuando la acepte aparecerá en tu lista de amigos.',
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).pop(); // volver al menú
            },
            child: const Text('Genial'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_done) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 80),
            const SizedBox(height: 16),
            const Text(
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
        MobileScanner(controller: _cam, onDetect: _onDetect),

        // Marco de escaneo
        Center(
          child: Container(
            width: 240,
            height: 240,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white, width: 3),
              borderRadius: BorderRadius.circular(16),
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
          Container(
            color: Colors.black.withOpacity(0.5),
            child: const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
          ),
      ],
    );
  }
}
