import 'dart:typed_data';

import 'package:image/image.dart' as img;

class CompressedImage {
  const CompressedImage({
    required this.bytes,
    required this.mimeType,
    required this.fileName,
    required this.width,
    required this.height,
  });

  final Uint8List bytes;
  final String mimeType;
  final String fileName;
  final int width;
  final int height;
}

class ImageCompressionException implements Exception {
  const ImageCompressionException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Validates and compresses business logo images before upload.
class ImageCompressionService {
  static const allowedMimeTypes = <String>{
    'image/jpeg',
    'image/png',
    'image/webp',
  };
  static const maxSourceBytes = 12 * 1024 * 1024;
  static const maxOutputBytes = 1500 * 1024;
  static const maxEdge = 1200;

  Future<CompressedImage> prepareLogo({
    required Uint8List sourceBytes,
    required String fileName,
    String? mimeType,
  }) async {
    if (sourceBytes.isEmpty) {
      throw const ImageCompressionException('The selected image is empty.');
    }
    if (sourceBytes.lengthInBytes > maxSourceBytes) {
      throw const ImageCompressionException(
        'This image is too large. Please choose a smaller photo.',
      );
    }

    final normalizedMime = _normalizeMime(mimeType);
    if (normalizedMime != null && !allowedMimeTypes.contains(normalizedMime)) {
      throw const ImageCompressionException(
        'Unsupported image format. Use JPEG, PNG or WebP.',
      );
    }

    final detectedMime = _detectMimeFromBytes(sourceBytes);
    if (detectedMime != null && !allowedMimeTypes.contains(detectedMime)) {
      throw const ImageCompressionException(
        'Unsupported image format. Use JPEG, PNG or WebP.',
      );
    }

    final guessedMime = _guessMime(fileName);
    final effectiveMime =
        normalizedMime ??
        (guessedMime == 'application/octet-stream' ? null : guessedMime) ??
        detectedMime;
    if (effectiveMime == null || !allowedMimeTypes.contains(effectiveMime)) {
      throw const ImageCompressionException(
        'Unsupported image format. Use JPEG, PNG or WebP.',
      );
    }

    // Camera/gallery picks often omit mime type and file extension.
    // Decode first so we can still convert readable images to JPEG.
    final decoded = img.decodeImage(sourceBytes);
    if (decoded == null) {
      throw const ImageCompressionException(
        'This image could not be read. Please choose another file.',
      );
    }

    var working = img.bakeOrientation(decoded);
    if (working.width > maxEdge || working.height > maxEdge) {
      working = img.copyResize(
        working,
        width: working.width >= working.height ? maxEdge : null,
        height: working.height > working.width ? maxEdge : null,
        interpolation: img.Interpolation.average,
      );
    }

    var quality = 88;
    Uint8List output = Uint8List.fromList(img.encodeJpg(working, quality: quality));
    while (output.lengthInBytes > maxOutputBytes && quality > 55) {
      quality -= 8;
      output = Uint8List.fromList(img.encodeJpg(working, quality: quality));
    }
    if (output.lengthInBytes > maxOutputBytes) {
      throw const ImageCompressionException(
        'Unable to compress this image below the upload limit.',
      );
    }

    final safeName = fileName.toLowerCase().endsWith('.jpg')
        ? fileName
        : '${fileName.replaceAll(RegExp(r'\.[^.]+$'), '')}.jpg';

    return CompressedImage(
      bytes: output,
      mimeType: 'image/jpeg',
      fileName: safeName,
      width: working.width,
      height: working.height,
    );
  }

  String _guessMime(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    return 'application/octet-stream';
  }

  String? _normalizeMime(String? value) {
    final mime = value?.trim().toLowerCase();
    if (mime == null || mime.isEmpty) return null;
    return mime;
  }

  String? _detectMimeFromBytes(Uint8List sourceBytes) {
    final decoder = img.findDecoderForData(sourceBytes);
    if (decoder is img.JpegDecoder) return 'image/jpeg';
    if (decoder is img.PngDecoder) return 'image/png';
    if (decoder is img.WebPDecoder) return 'image/webp';
    if (decoder is img.GifDecoder) return 'image/gif';
    return null;
  }
}
