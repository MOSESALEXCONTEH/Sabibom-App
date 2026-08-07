import 'package:flutter/material.dart';

import '../../customers/domain/customer.dart';
import '../customer_messaging_service.dart';

/// WhatsApp logo (when usesWhatsApp) + SMS icon for customers with a phone.
class CustomerChannelIcons extends StatelessWidget {
  const CustomerChannelIcons({
    required this.customer,
    this.onWhatsApp,
    this.onSms,
    this.compact = true,
    super.key,
  });

  final Customer customer;
  final VoidCallback? onWhatsApp;
  final VoidCallback? onSms;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (!customer.hasPhone) return const SizedBox.shrink();
    final size = compact ? 20.0 : 22.0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (customer.showWhatsAppBadge)
          IconButton(
            tooltip: 'WhatsApp',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            onPressed: onWhatsApp,
            icon: Icon(
              Icons.chat,
              size: size,
              color: const Color(0xFF25D366),
            ),
          ),
        IconButton(
          tooltip: 'SMS',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          onPressed: onSms,
          icon: Icon(
            Icons.sms_outlined,
            size: size,
            color: const Color(0xFF5B3DF5),
          ),
        ),
      ],
    );
  }
}

Future<MessageChannel?> showMessageChannelSheet(
  BuildContext context, {
  required Customer customer,
  bool allowWhatsAppWithoutFlag = false,
}) {
  final whatsappOk = customer.hasPhone &&
      (customer.usesWhatsApp || allowWhatsAppWithoutFlag);
  return showModalBottomSheet<MessageChannel>(
    context: context,
    showDragHandle: true,
    builder: (context) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                'Message ${customer.name}',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              if (whatsappOk)
                ListTile(
                  leading: const Icon(
                    Icons.chat,
                    color: Color(0xFF25D366),
                  ),
                  title: const Text('WhatsApp'),
                  subtitle: Text(customer.phone ?? ''),
                  onTap: () => Navigator.pop(context, MessageChannel.whatsapp),
                ),
              if (customer.hasPhone)
                ListTile(
                  leading: const Icon(
                    Icons.sms_outlined,
                    color: Color(0xFF5B3DF5),
                  ),
                  title: const Text('SMS / Phone messages'),
                  subtitle: Text(customer.phone ?? ''),
                  onTap: () => Navigator.pop(context, MessageChannel.sms),
                ),
              if (!customer.hasPhone)
                const Text('This customer has no phone number.'),
              if (customer.hasPhone && !whatsappOk)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Tip: turn on “Uses WhatsApp” on the customer to show the WhatsApp logo.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF667085)),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}
