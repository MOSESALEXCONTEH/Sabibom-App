import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'phone_e164.dart';

class MessagingException implements Exception {
  const MessagingException(this.message);
  final String message;

  @override
  String toString() => message;
}

enum MessageChannel { whatsapp, sms }

class CustomerMessagingService {
  Future<bool> canMessage(String? phone) async => PhoneE164.canMessage(phone);

  Future<void> openWhatsApp({
    required String phone,
    String? text,
  }) async {
    final digits = PhoneE164.toWhatsAppDigits(phone);
    if (digits.isEmpty) {
      throw const MessagingException(
        'This customer does not have a valid phone number.',
      );
    }
    final uri = Uri.parse(
      text == null || text.trim().isEmpty
          ? 'https://wa.me/$digits'
          : 'https://wa.me/$digits?text=${Uri.encodeComponent(text.trim())}',
    );
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) {
      throw const MessagingException(
        'Could not open WhatsApp. Make sure WhatsApp is installed.',
      );
    }
  }

  Future<void> openSms({
    required String phone,
    String? text,
  }) async {
    final digits = PhoneE164.toWhatsAppDigits(phone);
    if (digits.isEmpty) {
      throw const MessagingException(
        'This customer does not have a valid phone number.',
      );
    }
    final body = text?.trim() ?? '';
    final uri = Uri(
      scheme: 'sms',
      path: '+$digits',
      queryParameters: body.isEmpty ? null : <String, String>{'body': body},
    );
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) {
      throw const MessagingException(
        'Could not open the messaging app on this device.',
      );
    }
  }

  /// Best-effort: share PDF via the system share sheet (owner can pick WhatsApp).
  Future<void> sharePdfForWhatsApp({
    required File pdfFile,
    required String phone,
    String? text,
  }) async {
    final digits = PhoneE164.toWhatsAppDigits(phone);
    final caption = text?.trim().isNotEmpty == true
        ? text!.trim()
        : (digits.isEmpty
              ? 'SabiBom receipt'
              : 'SabiBom receipt for +$digits');
    await SharePlus.instance.share(
      ShareParams(
        files: <XFile>[XFile(pdfFile.path, mimeType: 'application/pdf')],
        text: caption,
        subject: 'SabiBom Receipt',
      ),
    );
  }

  Future<void> openChannel({
    required MessageChannel channel,
    required String phone,
    String? text,
  }) async {
    switch (channel) {
      case MessageChannel.whatsapp:
        await openWhatsApp(phone: phone, text: text);
      case MessageChannel.sms:
        await openSms(phone: phone, text: text);
    }
  }
}

final customerMessagingServiceProvider = Provider<CustomerMessagingService>(
  (ref) => CustomerMessagingService(),
);
