// lib/views/image_helpers.dart
//
// Utilidades de imagen compartidas (entrenamiento y perfil):
//   · pickCompressedImage()  → hoja Galería / Cámara y devuelve bytes JPEG
//                              ya reducidos (image_picker hace la compresión).
//   · Base64ImageCache       → decodifica una sola vez cada imagen base64.
//   · Base64Thumb            → miniatura que al pulsarla se abre en grande.
//   · openFullScreenImage()  → visor a pantalla completa con zoom.
//
// Las imágenes se guardan en base64 dentro del propio documento (SQLite y
// Firestore), por eso se reducen mucho: un documento de Firestore admite
// como máximo 1 MB.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

/// Tamaño máximo aceptado tras comprimir (bytes JPEG, antes de base64).
const int kMaxImageBytes = 600 * 1024;

/// Muestra la hoja Galería / Cámara y devuelve la imagen comprimida,
/// o null si el usuario cancela.
Future<Uint8List?> pickCompressedImage(
  BuildContext context, {
  double maxSide = 1080,
  int quality = 60,
}) async {
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Elegir de la galería'),
            onTap: () => Navigator.pop(ctx, ImageSource.gallery),
          ),
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Hacer una foto'),
            onTap: () => Navigator.pop(ctx, ImageSource.camera),
          ),
        ],
      ),
    ),
  );
  if (source == null) return null;

  try {
    final file = await ImagePicker().pickImage(
      source: source,
      maxWidth: maxSide,
      maxHeight: maxSide,
      imageQuality: quality,
    );
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    if (bytes.lengthInBytes > kMaxImageBytes) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('La imagen es demasiado grande. Prueba con otra.'),
          ),
        );
      }
      return null;
    }
    return bytes;
  } catch (e) {
    debugPrint('❌ Error eligiendo imagen: $e');
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No se pudo abrir la imagen. Revisa los permisos de cámara/fotos.',
          ),
        ),
      );
    }
    return null;
  }
}

/// Cache de decodificación base64 → bytes (evita decodificar en cada build).
class Base64ImageCache {
  Base64ImageCache._();
  static final Map<int, Uint8List> _cache = {};
  static const int _maxEntries = 40;

  static Uint8List? bytes(String b64) {
    if (b64.isEmpty) return null;
    final key = Object.hash(b64.length, b64.hashCode);
    final hit = _cache[key];
    if (hit != null) return hit;
    try {
      final decoded = base64Decode(b64);
      if (_cache.length >= _maxEntries) _cache.remove(_cache.keys.first);
      _cache[key] = decoded;
      return decoded;
    } catch (_) {
      return null;
    }
  }

  static String encode(Uint8List bytes) => base64Encode(bytes);
}

/// Miniatura de una imagen base64. Al pulsarla se abre a pantalla completa.
class Base64Thumb extends StatelessWidget {
  final String base64Data;
  final double width;
  final double height;
  final String heroTag;
  final double radius;

  const Base64Thumb({
    Key? key,
    required this.base64Data,
    required this.heroTag,
    this.width = 120,
    this.height = 80,
    this.radius = 10,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final bytes = Base64ImageCache.bytes(base64Data);
    if (bytes == null) return const SizedBox.shrink();
    return GestureDetector(
      onTap: () => openFullScreenImage(context, bytes, heroTag: heroTag),
      child: Hero(
        tag: heroTag,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: Image.memory(
            bytes,
            width: width,
            height: height,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            // Decodifica a un tamaño razonable (pantallas 3x) si el ancho es fijo.
            cacheWidth: width.isFinite ? (width * 3).round() : null,
          ),
        ),
      ),
    );
  }
}

/// Visor a pantalla completa con zoom (pellizcar) y cierre al tocar.
Future<void> openFullScreenImage(
  BuildContext context,
  Uint8List bytes, {
  required String heroTag,
}) {
  return Navigator.of(context).push(
    PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black,
      pageBuilder: (_, __, ___) =>
          _FullScreenImage(bytes: bytes, heroTag: heroTag),
      transitionsBuilder: (_, anim, __, child) =>
          FadeTransition(opacity: anim, child: child),
    ),
  );
}

class _FullScreenImage extends StatelessWidget {
  final Uint8List bytes;
  final String heroTag;

  const _FullScreenImage({required this.bytes, required this.heroTag});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: InteractiveViewer(
                  minScale: 1,
                  maxScale: 5,
                  child: Center(
                    child: Hero(
                      tag: heroTag,
                      child: Image.memory(bytes, fit: BoxFit.contain),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 28),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
