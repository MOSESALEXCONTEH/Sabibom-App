import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../dashboard/application/dashboard_providers.dart';
import '../../messaging/customer_messaging_service.dart';
import '../../sabi/application/sabi_providers.dart';
import '../../sabi/data/firebase_sabi_repository.dart';
import '../application/customers_providers.dart';
import '../domain/customer.dart';

enum _MessageType {
  greeting,
  newProduct,
  promo,
  thankYou,
  custom;

  String get apiValue => switch (this) {
    _MessageType.greeting => 'greeting',
    _MessageType.newProduct => 'new_product',
    _MessageType.promo => 'promo',
    _MessageType.thankYou => 'thank_you',
    _MessageType.custom => 'custom',
  };

  String get label => switch (this) {
    _MessageType.greeting => 'Greeting',
    _MessageType.newProduct => 'New product',
    _MessageType.promo => 'Promo',
    _MessageType.thankYou => 'Thank you',
    _MessageType.custom => 'Custom',
  };
}

class CustomerMessageCampaignScreen extends ConsumerStatefulWidget {
  const CustomerMessageCampaignScreen({this.preselectedCustomerId, super.key});

  final String? preselectedCustomerId;

  @override
  ConsumerState<CustomerMessageCampaignScreen> createState() =>
      _CustomerMessageCampaignScreenState();
}

class _CustomerMessageCampaignScreenState
    extends ConsumerState<CustomerMessageCampaignScreen> {
  final _notes = TextEditingController();
  final _message = TextEditingController();
  final _search = TextEditingController();
  final _selected = <String>{};
  var _type = _MessageType.greeting;
  var _channel = MessageChannel.sms;
  var _drafting = false;
  var _sending = false;
  var _sendIndex = 0;
  List<Customer> _sendQueue = const <Customer>[];

  @override
  void dispose() {
    _notes.dispose();
    _message.dispose();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = ref.watch(activeBusinessProvider).asData?.value;
    if (active is! ActiveBusinessData) {
      return Scaffold(
        appBar: AppBar(title: const Text('Message customers')),
        body: const Center(
          child: Text('Set up or select a business to continue.'),
        ),
      );
    }
    final business = active.business;
    final customersAsync = ref.watch(
      customersListProvider(business.businessId),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Message customers')),
      body: customersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: FilledButton.tonal(
            onPressed: () =>
                ref.invalidate(customersListProvider(business.businessId)),
            child: const Text('Retry'),
          ),
        ),
        data: (customers) {
          final withPhone = customers
              .where((c) => c.isActive && c.hasPhone)
              .toList();
          _ensurePreselect(withPhone);
          final query = _search.text.trim().toLowerCase();
          final visible = withPhone.where((c) {
            if (query.isEmpty) return true;
            return c.name.toLowerCase().contains(query) ||
                (c.phone ?? '').toLowerCase().contains(query);
          }).toList();

          if (_sending && _sendQueue.isNotEmpty) {
            return _SendingPanel(
              current: _sendQueue[_sendIndex],
              index: _sendIndex,
              total: _sendQueue.length,
              channel: _channel,
              onOpen: () => _openCurrent(business.name),
              onNext: _advanceSend,
              onCancel: () => setState(() {
                _sending = false;
                _sendQueue = const <Customer>[];
                _sendIndex = 0;
              }),
            );
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
            children: <Widget>[
              Text(
                '1. Ask Sabi to draft a message',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _MessageType.values.map((type) {
                  return ChoiceChip(
                    label: Text(type.label),
                    selected: _type == type,
                    onSelected: (_) => setState(() => _type = type),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _notes,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Notes for Sabi (optional)',
                  hintText: 'e.g. 10% off rice this weekend',
                ),
              ),
              const SizedBox(height: 8),
              FilledButton.tonalIcon(
                onPressed: _drafting
                    ? null
                    : () => _draftWithSabi(
                        businessId: business.businessId,
                        businessName: business.name,
                        customers: withPhone,
                      ),
                icon: _drafting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_awesome),
                label: Text(_drafting ? 'Drafting...' : 'Draft with Sabi'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _message,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Message preview',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                '2. Choose channel',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              SegmentedButton<MessageChannel>(
                segments: const <ButtonSegment<MessageChannel>>[
                  ButtonSegment(
                    value: MessageChannel.sms,
                    label: Text('SMS'),
                    icon: Icon(Icons.sms_outlined),
                  ),
                  ButtonSegment(
                    value: MessageChannel.whatsapp,
                    label: Text('WhatsApp'),
                    icon: Icon(Icons.chat),
                  ),
                ],
                selected: <MessageChannel>{_channel},
                onSelectionChanged: (value) {
                  setState(() => _channel = value.first);
                },
              ),
              if (_channel == MessageChannel.whatsapp)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'WhatsApp send uses customers marked “Uses WhatsApp”. '
                    'You will confirm each chat in WhatsApp.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF667085)),
                  ),
                ),
              const SizedBox(height: 24),
              Text(
                '3. Select customers',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search customers',
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _selected
                          ..clear()
                          ..addAll(
                            _eligible(withPhone).map((c) => c.id),
                          );
                      });
                    },
                    child: const Text('Select all eligible'),
                  ),
                  TextButton(
                    onPressed: () => setState(_selected.clear),
                    child: const Text('Clear'),
                  ),
                ],
              ),
              ...visible.map((customer) {
                final eligible = _isEligible(customer);
                return CheckboxListTile(
                  value: _selected.contains(customer.id),
                  onChanged: eligible
                      ? (checked) {
                          setState(() {
                            if (checked == true) {
                              _selected.add(customer.id);
                            } else {
                              _selected.remove(customer.id);
                            }
                          });
                        }
                      : null,
                  title: Text(customer.name),
                  subtitle: Text(customer.phone ?? ''),
                  secondary: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      if (customer.showWhatsAppBadge)
                        const Icon(
                          Icons.chat,
                          size: 18,
                          color: Color(0xFF25D366),
                        ),
                      if (customer.hasPhone)
                        const Padding(
                          padding: EdgeInsets.only(left: 4),
                          child: Icon(
                            Icons.sms_outlined,
                            size: 18,
                            color: Color(0xFF5B3DF5),
                          ),
                        ),
                    ],
                  ),
                );
              }),
              if (visible.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text('No customers with phone numbers match.'),
                ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _selected.isEmpty || _message.text.trim().isEmpty
                    ? null
                    : () => _startSend(withPhone),
                child: Text(
                  'Send to ${_selected.length} customer${_selected.length == 1 ? '' : 's'}',
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _ensurePreselect(List<Customer> withPhone) {
    final id = widget.preselectedCustomerId?.trim();
    if (id == null || id.isEmpty) return;
    if (_selected.contains(id)) return;
    final match = withPhone.where((c) => c.id == id).firstOrNull;
    if (match != null && _isEligible(match)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _selected.add(id));
      });
    }
  }

  bool _isEligible(Customer customer) {
    if (!customer.hasPhone) return false;
    if (_channel == MessageChannel.whatsapp) return customer.usesWhatsApp;
    return true;
  }

  Iterable<Customer> _eligible(List<Customer> customers) =>
      customers.where(_isEligible);

  Future<void> _draftWithSabi({
    required String businessId,
    required String businessName,
    required List<Customer> customers,
  }) async {
    setState(() => _drafting = true);
    try {
      final selectedName = _selected.length == 1
          ? customers.where((c) => c.id == _selected.first).firstOrNull?.name
          : null;
      final message = await ref
          .read(sabiRepositoryProvider)
          .composeCustomerMessage(
            businessId: businessId,
            messageType: _type.apiValue,
            notes: _notes.text.trim(),
            customerName: selectedName,
            businessName: businessName,
          );
      if (!mounted) return;
      setState(() => _message.text = message);
    } on SabiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sabi could not draft that message. Try again.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _drafting = false);
    }
  }

  void _startSend(List<Customer> withPhone) {
    final queue = withPhone
        .where((c) => _selected.contains(c.id) && _isEligible(c))
        .toList();
    if (queue.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _channel == MessageChannel.whatsapp
                ? 'Select customers marked “Uses WhatsApp”.'
                : 'Select at least one customer with a phone number.',
          ),
        ),
      );
      return;
    }
    setState(() {
      _sending = true;
      _sendQueue = queue;
      _sendIndex = 0;
    });
  }

  Future<void> _openCurrent(String businessName) async {
    final customer = _sendQueue[_sendIndex];
    final text = _message.text.trim();
    final messaging = ref.read(customerMessagingServiceProvider);
    try {
      await messaging.openChannel(
        channel: _channel,
        phone: customer.phone!,
        text: text,
      );
    } on MessagingException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  void _advanceSend() {
    if (_sendIndex >= _sendQueue.length - 1) {
      setState(() {
        _sending = false;
        _sendQueue = const <Customer>[];
        _sendIndex = 0;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Finished messaging selected customers.')),
      );
      return;
    }
    setState(() => _sendIndex += 1);
  }
}

class _SendingPanel extends StatelessWidget {
  const _SendingPanel({
    required this.current,
    required this.index,
    required this.total,
    required this.channel,
    required this.onOpen,
    required this.onNext,
    required this.onCancel,
  });

  final Customer current;
  final int index;
  final int total;
  final MessageChannel channel;
  final VoidCallback onOpen;
  final VoidCallback onNext;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Text(
            'Sending ${index + 1} of $total',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            current.name,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          Text(current.phone ?? '', style: const TextStyle(color: AppColors.mutedText)),
          const SizedBox(height: 8),
          Text(
            channel == MessageChannel.whatsapp
                ? 'Open WhatsApp, send, then tap Next.'
                : 'Open SMS, send, then tap Next.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: onOpen,
            icon: Icon(
              channel == MessageChannel.whatsapp
                  ? Icons.chat
                  : Icons.sms_outlined,
            ),
            label: Text(
              channel == MessageChannel.whatsapp
                  ? 'Open WhatsApp'
                  : 'Open SMS',
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.tonal(
            onPressed: onNext,
            child: Text(index >= total - 1 ? 'Done' : 'Next customer'),
          ),
          TextButton(onPressed: onCancel, child: const Text('Cancel')),
        ],
      ),
    );
  }
}
