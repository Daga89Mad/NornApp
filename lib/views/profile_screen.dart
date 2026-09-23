// lib/views/profile_screen.dart
//
// Editar perfil: cambiar nombre de usuario e imagen.
// Se abre desde el lápiz de la cabecera del menú principal.

import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../core/profile_service.dart';
import 'image_helpers.dart';

class ProfileScreen extends StatefulWidget {
  final Color accent;
  const ProfileScreen({Key? key, this.accent = Colors.indigo})
    : super(key: key);

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _service = ProfileService.instance;
  late final TextEditingController _nameCtrl;

  Uint8List? _photo; // lo que se ve ahora (puede no estar guardado aún)
  bool _photoChanged = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: _service.name.value);
    _photo = _service.photo.value;
    _service.load(force: true).then((_) {
      if (!mounted) return;
      setState(() {
        if (_nameCtrl.text.trim().isEmpty) {
          _nameCtrl.text = _service.name.value;
        }
        if (!_photoChanged) _photo = _service.photo.value;
      });
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _changePhoto() async {
    final hasPhoto = _photo != null;
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: const Text('Elegir nueva imagen'),
              onTap: () => Navigator.pop(ctx, 'pick'),
            ),
            if (hasPhoto)
              ListTile(
                leading: const Icon(Icons.zoom_in),
                title: const Text('Ver en grande'),
                onTap: () => Navigator.pop(ctx, 'view'),
              ),
            if (hasPhoto)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text(
                  'Quitar imagen',
                  style: TextStyle(color: Colors.red),
                ),
                onTap: () => Navigator.pop(ctx, 'remove'),
              ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;

    switch (action) {
      case 'pick':
        // Foto de perfil: pequeña (256 px) porque se guarda en el perfil.
        final bytes = await pickCompressedImage(
          context,
          maxSide: 256,
          quality: 75,
        );
        if (bytes != null && mounted) {
          setState(() {
            _photo = bytes;
            _photoChanged = true;
          });
        }
        break;
      case 'view':
        if (_photo != null) {
          openFullScreenImage(context, _photo!, heroTag: 'profile_photo');
        }
        break;
      case 'remove':
        setState(() {
          _photo = null;
          _photoChanged = true;
        });
        break;
    }
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El nombre no puede estar vacío')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await _service.save(
        newName: name,
        newPhoto: _photoChanged ? _photo : null,
        removePhoto: _photoChanged && _photo == null,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Perfil actualizado')));
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo guardar el perfil: $e'),
          backgroundColor: Colors.red.shade600,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent;
    final email = FirebaseAuth.instance.currentUser?.email ?? '';
    final initial = _nameCtrl.text.trim().isNotEmpty
        ? _nameCtrl.text.trim()[0].toUpperCase()
        : 'U';

    return Scaffold(
      appBar: AppBar(title: const Text('Mi perfil')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          children: [
            // ── Avatar ──────────────────────────────────────────────────────
            Center(
              child: GestureDetector(
                onTap: _saving ? null : _changePhoto,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Hero(
                      tag: 'profile_photo',
                      child: CircleAvatar(
                        radius: 56,
                        backgroundColor: accent.withOpacity(0.12),
                        backgroundImage: _photo != null
                            ? MemoryImage(_photo!)
                            : null,
                        child: _photo == null
                            ? Text(
                                initial,
                                style: TextStyle(
                                  fontSize: 40,
                                  fontWeight: FontWeight.bold,
                                  color: accent,
                                ),
                              )
                            : null,
                      ),
                    ),
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: accent,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                        ),
                        child: const Icon(
                          Icons.photo_camera,
                          size: 18,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: TextButton(
                onPressed: _saving ? null : _changePhoto,
                child: const Text('Cambiar imagen'),
              ),
            ),
            const SizedBox(height: 24),

            // ── Nombre ──────────────────────────────────────────────────────
            TextField(
              controller: _nameCtrl,
              enabled: !_saving,
              textCapitalization: TextCapitalization.words,
              maxLength: 40,
              decoration: const InputDecoration(
                labelText: 'Nombre de usuario',
                prefixIcon: Icon(Icons.person_outline),
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}), // refresca la inicial
            ),
            const SizedBox(height: 12),

            // ── Email (solo lectura) ────────────────────────────────────────
            InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Correo',
                prefixIcon: Icon(Icons.mail_outline),
                border: OutlineInputBorder(),
                enabled: false,
              ),
              child: Text(email, style: TextStyle(color: Colors.grey.shade700)),
            ),
            const SizedBox(height: 8),
            Text(
              'Tus amigos verán este nombre y esta imagen.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 28),

            SizedBox(
              height: 48,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: Colors.white,
                ),
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text(_saving ? 'Guardando…' : 'Guardar cambios'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
