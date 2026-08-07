import 'dart:io';
import 'dart:typed_data';

import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

/// Result of saving a receipt PDF to durable storage.
class ReceiptPdfSaveResult {
  const ReceiptPdfSaveResult({
    required this.file,
    required this.savedToDownloads,
  });

  final File file;

  /// True when the file was also copied into the public Downloads folder.
  final bool savedToDownloads;
}

class ReceiptShareService {
  String _safeName(String receiptNumber) =>
      receiptNumber.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');

  Future<File> writeTempPdf({
    required Uint8List bytes,
    required String receiptNumber,
  }) async {
    final dir = await getTemporaryDirectory();
    final file = File(
      p.join(dir.path, 'SabiBom_Receipt_${_safeName(receiptNumber)}.pdf'),
    );
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  /// Saves the PDF where the merchant can find it again.
  ///
  /// Always writes under the app documents `Receipts` folder. On Android,
  /// also copies into the public Downloads folder when the OS allows it.
  Future<ReceiptPdfSaveResult> downloadPdf({
    required Uint8List bytes,
    required String receiptNumber,
  }) async {
    final fileName = 'SabiBom_Receipt_${_safeName(receiptNumber)}.pdf';
    final docs = await getApplicationDocumentsDirectory();
    final receiptsDir = Directory(p.join(docs.path, 'Receipts'));
    if (!await receiptsDir.exists()) {
      await receiptsDir.create(recursive: true);
    }
    final localFile = File(p.join(receiptsDir.path, fileName));
    await localFile.writeAsBytes(bytes, flush: true);

    var savedToDownloads = false;
    if (Platform.isAndroid) {
      try {
        final downloads = await getDownloadsDirectory();
        if (downloads != null) {
          final downloadFile = File(p.join(downloads.path, fileName));
          await downloadFile.writeAsBytes(bytes, flush: true);
          savedToDownloads = true;
          return ReceiptPdfSaveResult(
            file: downloadFile,
            savedToDownloads: true,
          );
        }
      } catch (_) {
        // Fall through to the app documents copy.
      }
    }

    return ReceiptPdfSaveResult(
      file: localFile,
      savedToDownloads: savedToDownloads,
    );
  }

  /// Opens [file] with the phone's installed PDF readers / apps.
  Future<OpenResult> openPdf(File file) {
    return OpenFilex.open(file.path, type: 'application/pdf');
  }

  /// Saves then opens the receipt in an external PDF reader.
  Future<OpenResult> downloadAndOpenPdf({
    required Uint8List bytes,
    required String receiptNumber,
  }) async {
    final saved = await downloadPdf(
      bytes: bytes,
      receiptNumber: receiptNumber,
    );
    return openPdf(saved.file);
  }

  Future<void> sharePdf({
    required Uint8List bytes,
    required String receiptNumber,
  }) async {
    final file = await writeTempPdf(bytes: bytes, receiptNumber: receiptNumber);
    await SharePlus.instance.share(
      ShareParams(
        files: <XFile>[XFile(file.path, mimeType: 'application/pdf')],
        subject: 'SabiBom Receipt $receiptNumber',
        text: 'SabiBom receipt $receiptNumber',
      ),
    );
  }

  Future<void> printPdf(Uint8List bytes) async {
    await Printing.layoutPdf(onLayout: (_) async => bytes);
  }

  Future<void> previewPdf(Uint8List bytes) async {
    await Printing.layoutPdf(onLayout: (_) async => bytes);
  }
}
