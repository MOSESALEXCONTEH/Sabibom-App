import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sabibom/core/services/image_compression_service.dart';

Uint8List _jpegBytes({int width = 100, int height = 80}) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(90, 60, 240));
  return Uint8List.fromList(img.encodeJpg(image));
}

Uint8List _pngBytes({int width = 100, int height = 80}) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(20, 160, 90));
  return Uint8List.fromList(img.encodePng(image));
}

void main() {
  final service = ImageCompressionService();

  test('JPEG succeeds', () async {
    final result = await service.prepareLogo(
      sourceBytes: _jpegBytes(),
      fileName: 'logo.jpg',
      mimeType: 'image/jpeg',
    );

    expect(result.bytes, isNotEmpty);
    expect(result.mimeType, 'image/jpeg');
    expect(result.width, greaterThan(0));
    expect(result.height, greaterThan(0));
  });

  test('PNG succeeds', () async {
    final result = await service.prepareLogo(
      sourceBytes: _pngBytes(),
      fileName: 'logo.png',
      mimeType: 'image/png',
    );

    expect(result.bytes, isNotEmpty);
    expect(result.mimeType, 'image/jpeg');
    expect(result.width, greaterThan(0));
    expect(result.height, greaterThan(0));
  });

  test('supported image output is returned', () async {
    final result = await service.prepareLogo(
      sourceBytes: _jpegBytes(width: 2400, height: 1800),
      fileName: 'shop.png',
      mimeType: 'image/png',
    );

    expect(result.mimeType, 'image/jpeg');
    expect(result.fileName, 'shop.jpg');
    expect(result.width <= 1200, isTrue);
    expect(result.height <= 1200, isTrue);
    expect(result.bytes.lengthInBytes, lessThan(1500 * 1024));
  });

  test('unsupported MIME type throws ImageCompressionException', () async {
    expect(
      () => service.prepareLogo(
        sourceBytes: _jpegBytes(),
        fileName: 'logo.gif',
        mimeType: 'image/gif',
      ),
      throwsA(isA<ImageCompressionException>()),
    );
  });

  test('empty bytes are rejected', () async {
    expect(
      () => service.prepareLogo(
        sourceBytes: Uint8List(0),
        fileName: 'logo.jpg',
        mimeType: 'image/jpeg',
      ),
      throwsA(isA<ImageCompressionException>()),
    );
  });

  test('invalid/corrupt image data is handled safely', () async {
    expect(
      () => service.prepareLogo(
        sourceBytes: Uint8List.fromList('not-an-image'.codeUnits),
        fileName: 'logo.jpg',
        mimeType: 'image/jpeg',
      ),
      throwsA(
        isA<ImageCompressionException>().having(
          (e) => e.message,
          'message',
          'This image could not be read. Please choose another file.',
        ),
      ),
    );
  });

  test('error messages do not expose file contents', () async {
    const sensitiveName = 'secret-inline-token-123';
    final payload = Uint8List.fromList(sensitiveName.codeUnits);

    try {
      await service.prepareLogo(
        sourceBytes: payload,
        fileName: 'upload.bin',
        mimeType: 'application/octet-stream',
      );
      fail('Expected ImageCompressionException.');
    } on ImageCompressionException catch (error) {
      expect(error.message.contains(sensitiveName), isFalse);
      expect(error.message, isNotEmpty);
    }
  });

  test('existing callers still handle the exception safely', () async {
    String? shownMessage;
    try {
      await service.prepareLogo(
        sourceBytes: _jpegBytes(),
        fileName: 'logo.gif',
        mimeType: 'image/gif',
      );
    } on ImageCompressionException catch (error) {
      shownMessage = error.message;
    }

    expect(shownMessage, 'Unsupported image format. Use JPEG, PNG or WebP.');
  });
}
