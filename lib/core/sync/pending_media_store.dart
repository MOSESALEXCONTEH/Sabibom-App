import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../services/image_compression_service.dart';

Future<String> persistPendingImage({
  required String id,
  required CompressedImage image,
}) async {
  final root = await getApplicationDocumentsDirectory();
  final directory = Directory(path.join(root.path, 'pending_media'));
  if (!await directory.exists()) await directory.create(recursive: true);
  final safeId = id.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
  final file = File(path.join(directory.path, '$safeId.jpg'));
  await file.writeAsBytes(image.bytes, flush: true);
  return file.path;
}
