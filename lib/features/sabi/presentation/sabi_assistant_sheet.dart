import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/theme/app_colors.dart';
import '../../dashboard/application/dashboard_providers.dart';
import '../application/sabi_controller.dart';
import '../application/sabi_providers.dart';
import '../domain/sabi_action.dart';
import '../domain/sabi_intent.dart';
import '../domain/sabi_message.dart';
import 'sabi_navigation.dart';
import 'widgets/sabi_message_bubble.dart';
import 'widgets/sabi_prompt_chip.dart';

const _suggestedPrompts = <String>[
  'How many customers do I have?',
  'How much did I sell today?',
  'Which products are running low?',
  'Which products are expiring soon?',
  'Who owes me money?',
  'How much did I spend this week?',
  'What do I owe suppliers?',
  'Make a receipt: 2 rice at 50 Le',
];

/// True when the instruction is about saving a customer or product,
/// which Sabi handles with a structured action + confirmation.
bool _looksLikeDataAction(String text) => sabiLooksLikeDataAction(text);

bool _looksLikeSale(String text) => sabiLooksLikeSaleDraft(text);

const _privacyAcceptedKey = 'sabi_ai_privacy_accepted_v1';

class SabiAssistantSheet extends ConsumerStatefulWidget {
  const SabiAssistantSheet({super.key});

  @override
  ConsumerState<SabiAssistantSheet> createState() => _SabiAssistantSheetState();
}

class _SabiAssistantSheetState extends ConsumerState<SabiAssistantSheet>
    with SingleTickerProviderStateMixin {
  final _inputController = TextEditingController();
  final _focusNode = FocusNode();
  var _privacyReady = false;
  var _privacyAccepted = false;
  var _listening = false;
  var _isHandingOff = false;
  var _soundLevel = 0.0;
  String? _copiedMessageId;
  late final AnimationController _micPulse;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(sabiAssistantControllerProvider.notifier).startFreshSession();
    });
    _micPulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _loadPrivacy();
  }

  Future<void> _copyMessage(SabiMessage message) async {
    await Clipboard.setData(ClipboardData(text: message.text));
    if (!mounted) return;
    setState(() => _copiedMessageId = message.id);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Message copied')));
    await Future<void>.delayed(const Duration(seconds: 2));
    if (mounted && _copiedMessageId == message.id) {
      setState(() => _copiedMessageId = null);
    }
  }

  void _editMessage(SabiMessage message) {
    ref.read(sabiAssistantControllerProvider.notifier).editMessage(message.id);
    _inputController
      ..text = message.text
      ..selection = TextSelection.collapsed(offset: message.text.length);
    _focusNode.requestFocus();
  }

  Future<void> _loadPrivacy() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _privacyAccepted = prefs.getBool(_privacyAcceptedKey) ?? false;
      _privacyReady = true;
    });
  }

  Future<bool> _ensurePrivacyAccepted() async {
    if (_privacyAccepted) return true;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sabi AI privacy'),
        content: const Text(
          'Sabi sends only the minimum needed for your request — such as your '
          'spoken instruction or a verified summary — to a secure server. '
          'It does not send passwords, full customer databases, or API keys. '
          'You can cancel and continue selling manually.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (accepted != true) return false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_privacyAcceptedKey, true);
    if (mounted) setState(() => _privacyAccepted = true);
    return true;
  }

  @override
  void deactivate() {
    if (_listening) {
      ref.read(sabiSpeechServiceProvider).cancel();
      _listening = false;
      _soundLevel = 0;
      _micPulse.stop();
    }
    super.deactivate();
  }

  @override
  void dispose() {
    _micPulse.dispose();
    _inputController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// Close the sheet and let the parent context own route navigation.
  void _handOff(SabiSheetResult result) {
    if (_isHandingOff || !mounted) return;
    _isHandingOff = true;
    Navigator.of(context).pop(result);
  }

  Future<void> _submit(String? businessId, {bool fromVoice = false}) async {
    final question = _inputController.text;
    if (businessId == null || businessId.trim().isEmpty) return;
    if (_isHandingOff) return;
    if (!await _ensurePrivacyAccepted()) return;
    if (!mounted || _isHandingOff) return;
    final submitted = question.trim();
    if (submitted.isEmpty) return;
    _inputController.clear();

    // Sale/receipt instructions open the draft once — never push from this sheet.
    final clarification = sabiClarificationFor(submitted);
    if (clarification == null &&
        !_looksLikeDataAction(submitted) &&
        _looksLikeSale(submitted)) {
      ref
          .read(sabiAssistantControllerProvider.notifier)
          .cancelPendingClarificationQuietly();
      _handOff(SabiOpenSaleDraft(query: submitted));
      return;
    }

    final notifier = ref.read(sabiAssistantControllerProvider.notifier);
    final hasPendingClarification =
        ref.read(sabiAssistantControllerProvider).pendingClarificationIntent !=
        null;
    if (_looksLikeDataAction(submitted) ||
        clarification != null ||
        hasPendingClarification) {
      await notifier.parseAction(
        businessId: businessId,
        instruction: submitted,
        fromVoice: fromVoice,
      );
    } else {
      await notifier.ask(
        businessId: businessId,
        question: submitted,
        speakReply: fromVoice,
      );
    }
    if (!mounted || _isHandingOff) return;
    final action = ref.read(sabiAssistantControllerProvider).pendingAction;
    if (action == 'open_sale_draft') {
      ref.read(sabiAssistantControllerProvider.notifier).clearPendingAction();
      _handOff(SabiOpenSaleDraft(query: submitted.isEmpty ? null : submitted));
    } else if (action == 'open_expense_draft') {
      final pending = ref
          .read(sabiAssistantControllerProvider)
          .pendingSabiAction;
      ref.read(sabiAssistantControllerProvider.notifier).clearPendingAction();
      _handOff(
        SabiOpenExpenseDraft(
          amountMinor: pending?.expense?.amountMinor,
          description: pending?.expense?.description,
          categoryName: pending?.expense?.categoryName,
        ),
      );
      ref
          .read(sabiAssistantControllerProvider.notifier)
          .cancelPendingSabiActionQuietly();
    } else if (action == 'open_supplier_draft') {
      final pending = ref
          .read(sabiAssistantControllerProvider)
          .pendingSabiAction;
      ref.read(sabiAssistantControllerProvider.notifier).clearPendingAction();
      _handOff(
        SabiOpenSupplierDraft(
          name: pending?.supplier?.name,
          phone: pending?.supplier?.phone,
        ),
      );
      ref
          .read(sabiAssistantControllerProvider.notifier)
          .cancelPendingSabiActionQuietly();
    } else if (action == 'open_purchase_draft') {
      ref.read(sabiAssistantControllerProvider.notifier).clearPendingAction();
      _handOff(
        SabiOpenPurchaseDraft(query: submitted.isEmpty ? null : submitted),
      );
      ref
          .read(sabiAssistantControllerProvider.notifier)
          .cancelPendingSabiActionQuietly();
    }
  }

  Future<void> _toggleMic(String? businessId) async {
    if (businessId == null || _isHandingOff) return;
    if (_listening) {
      await _stopListening(businessId);
      return;
    }
    if (!await _ensurePrivacyAccepted()) return;
    if (!mounted || _isHandingOff || _listening) return;
    setState(() {
      _listening = true;
      _soundLevel = 0;
    });
    _micPulse.repeat(reverse: true);
    try {
      final speech = ref.read(sabiSpeechServiceProvider);
      await speech.startListening(
        seedText: _inputController.text,
        onPartial: (partial) {
          if (!mounted || !_listening) return;
          // Never wipe earlier words while the mic is still held.
          final current = _inputController.text.trim();
          if (partial.trim().isEmpty && current.isNotEmpty) return;
          if (partial.trim().length < current.length &&
              !partial.trim().toLowerCase().startsWith(current.toLowerCase()) &&
              !current.toLowerCase().startsWith(partial.trim().toLowerCase())) {
            // Keep the longer text across silence / segment restarts.
            return;
          }
          _inputController.text = partial;
          _inputController.selection = TextSelection.collapsed(
            offset: _inputController.text.length,
          );
        },
        onSoundLevel: (level) {
          if (!mounted || !_listening) return;
          // speech_to_text reports roughly -2..10; normalize for pulse.
          final normalized = ((level + 2) / 12).clamp(0.0, 1.0);
          setState(() => _soundLevel = normalized);
        },
      );
    } catch (error) {
      if (!mounted) return;
      _micPulse.stop();
      setState(() {
        _listening = false;
        _soundLevel = 0;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  Future<void> _stopListening(String? businessId) async {
    if (!_listening) return;
    final speech = ref.read(sabiSpeechServiceProvider);
    try {
      final text = await speech.stopListening();
      if (!mounted || _isHandingOff) return;
      _micPulse.stop();
      setState(() {
        _listening = false;
        _soundLevel = 0;
      });
      if (text.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Tap the mic, speak, then tap again to send.'),
          ),
        );
        return;
      }
      _inputController.text = text;
      if (!_looksLikeDataAction(text) && _looksLikeSale(text)) {
        _handOff(SabiOpenSaleDraft(query: text));
        return;
      }
      await _submit(businessId, fromVoice: true);
    } catch (error) {
      if (!mounted) return;
      _micPulse.stop();
      setState(() {
        _listening = false;
        _soundLevel = 0;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  Future<void> _confirmClearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear chat history?'),
        content: const Text(
          'This removes all Sabi messages on this device. You cannot undo this.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await ref.read(sabiAssistantControllerProvider.notifier).clearHistory();
  }

  @override
  Widget build(BuildContext context) {
    final activeBusiness = ref.watch(activeBusinessProvider).asData?.value;
    final businessId = activeBusiness is ActiveBusinessData
        ? activeBusiness.business.businessId
        : null;
    final isNoBusiness = activeBusiness is ActiveBusinessNone;
    final assistant = ref.watch(sabiAssistantControllerProvider);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final keyboardOpen = bottomInset > 0;
    final busy =
        assistant.isLoading ||
        _listening ||
        _isHandingOff ||
        SabiSaleDraftNavigator.isOpening;

    // Pad outside the sheet so the input rides above the keyboard instead of
    // being squeezed under it inside a fixed-height fraction.
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: FractionallySizedBox(
        heightFactor: keyboardOpen ? 1 : 0.76,
        alignment: Alignment.bottomCenter,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: context.isDarkTheme
                ? const Color(0xFF171C29)
                : const Color(0xFFFCFBFF),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: Column(
                children: <Widget>[
                  if (!keyboardOpen) ...<Widget>[
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFFD7D1E8),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _SheetHeader(
                      canClear: assistant.messages.isNotEmpty && !busy,
                      onClear: _confirmClearHistory,
                    ),
                    const SizedBox(height: 16),
                  ] else
                    const Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Ask Sabi',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  if (!_privacyReady || !assistant.isHistoryReady)
                    const Expanded(
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (isNoBusiness)
                    _NoBusinessContent(
                      onSetUp: () => _handOff(const SabiOpenBusinessSetup()),
                    )
                  else ...<Widget>[
                    if (!keyboardOpen) ...<Widget>[
                      FilledButton.tonalIcon(
                        onPressed: busy
                            ? null
                            : () async {
                                if (!await _ensurePrivacyAccepted()) {
                                  return;
                                }
                                if (!mounted || _isHandingOff) return;
                                _handOff(const SabiOpenSaleDraft());
                              },
                        icon: const Icon(Icons.point_of_sale_outlined),
                        label: const Text('Create Sale'),
                      ),
                      const SizedBox(height: 12),
                    ],
                    Expanded(
                      child: ListView(
                        reverse: false,
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        children: <Widget>[
                          if (assistant.messages.isEmpty &&
                              !keyboardOpen) ...<Widget>[
                            const Text(
                              'Ask about my business',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 10),
                            Column(
                              children: _suggestedPrompts
                                  .map(
                                    (prompt) => Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: SabiPromptChip(
                                        label: prompt,
                                        onPressed: busy
                                            ? null
                                            : () async {
                                                _inputController.text = prompt;
                                                await _submit(businessId);
                                              },
                                      ),
                                    ),
                                  )
                                  .toList(),
                            ),
                            const SizedBox(height: 24),
                          ],
                          ...assistant.messages.map(
                            (message) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: SabiMessageBubble(
                                message: message,
                                onCopy: () => _copyMessage(message),
                                isCopied: _copiedMessageId == message.id,
                                onEdit:
                                    message.author == SabiMessageAuthor.user &&
                                        !busy
                                    ? () => _editMessage(message)
                                    : null,
                              ),
                            ),
                          ),
                          if (assistant.pendingSabiAction != null)
                            _ActionConfirmationCard(
                              action: assistant.pendingSabiAction!,
                              busy: busy,
                              onConfirm: () => ref
                                  .read(
                                    sabiAssistantControllerProvider.notifier,
                                  )
                                  .confirmPendingSabiAction(
                                    businessId: businessId ?? '',
                                  ),
                              onCancel: () => ref
                                  .read(
                                    sabiAssistantControllerProvider.notifier,
                                  )
                                  .cancelPendingSabiAction(),
                            ),
                          if (busy && !_listening)
                            const Padding(
                              padding: EdgeInsets.only(top: 4),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              ),
                            ),
                          if (assistant.errorMessage != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                assistant.errorMessage!,
                                style: const TextStyle(
                                  color: Color(0xFFB42318),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Opacity(
                      opacity: _listening ? 1 : 0,
                      child: const Padding(
                        padding: EdgeInsets.only(bottom: 8),
                        child: Text(
                          'Listening… tap again to send',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF5B3DF5),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    _InputBar(
                      controller: _inputController,
                      focusNode: _focusNode,
                      enabled: businessId != null && (!busy || _listening),
                      listening: _listening,
                      soundLevel: _soundLevel,
                      pulse: _micPulse,
                      onSend: () => _submit(businessId),
                      onMicTap: () => _toggleMic(businessId),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SheetHeader extends StatelessWidget {
  const _SheetHeader({required this.canClear, required this.onClear});

  final bool canClear;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: context.brandTint,
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.auto_awesome,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Hi, I\'m Sabi',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              SizedBox(height: 3),
              Text(
                'Ask about your business, dictate with the mic, or create a sale.',
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Clear chat history',
          onPressed: canClear ? onClear : null,
          icon: const Icon(Icons.delete_outline),
        ),
      ],
    );
  }
}

class _NoBusinessContent extends StatelessWidget {
  const _NoBusinessContent({required this.onSetUp});

  final VoidCallback onSetUp;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.storefront_outlined,
              size: 40,
              color: Color(0xFF5B3DF5),
            ),
            const SizedBox(height: 16),
            const Text(
              'Set up your business first so Sabi can understand your sales, stock, customers and expenses.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onSetUp,
              child: const Text('Set Up Business'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionConfirmationCard extends StatelessWidget {
  const _ActionConfirmationCard({
    required this.action,
    required this.busy,
    required this.onConfirm,
    required this.onCancel,
  });

  final SabiAction action;
  final bool busy;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final customer = action.customer;
    final product = action.product;
    final rows = <(String, String)>[];
    String title;
    IconData icon;

    if (action.isAddCustomer && customer != null) {
      title = 'New customer';
      icon = Icons.person_add_alt_1_outlined;
      rows.add(('Name', customer.name));
      if (customer.phone != null) rows.add(('Phone', customer.phone!));
      if (customer.email != null) rows.add(('Email', customer.email!));
      if (customer.address != null) rows.add(('Address', customer.address!));
      if (customer.notes != null) rows.add(('Notes', customer.notes!));
    } else if (action.isAddProduct && product != null) {
      title = 'New product';
      icon = Icons.inventory_2_outlined;
      rows.add(('Name', product.name));
      if (product.sellingPriceMinor != null) {
        rows.add((
          'Selling price',
          (product.sellingPriceMinor! / 100).toStringAsFixed(2),
        ));
      }
      if (product.costPriceMinor != null) {
        rows.add((
          'Cost price',
          (product.costPriceMinor! / 100).toStringAsFixed(2),
        ));
      }
      if (product.quantity != null) {
        rows.add(('Quantity', '${product.quantity}'));
      }
      if (product.unit != null) rows.add(('Unit', product.unit!));
      if (product.categoryName != null) {
        rows.add(('Category', product.categoryName!));
      }
      if (product.description != null) {
        rows.add(('Description', product.description!));
      }
    } else if (action.canConfirmExpense && action.expense != null) {
      final expense = action.expense!;
      title = 'New expense';
      icon = Icons.payments_outlined;
      if (expense.amountMinor != null) {
        rows.add((
          'Amount',
          'Le ${(expense.amountMinor! / 100).toStringAsFixed(2)}',
        ));
      }
      if (expense.categoryName != null) {
        rows.add(('Category', expense.categoryName!));
      }
      if (expense.description != null) {
        rows.add(('Description', expense.description!));
      }
      if (expense.paymentMethod != null) {
        rows.add(('Payment', expense.paymentMethod!));
      }
    } else if (action.canConfirmSupplier && action.supplier != null) {
      final supplier = action.supplier!;
      title = 'New supplier';
      icon = Icons.local_shipping_outlined;
      if (supplier.name != null) rows.add(('Name', supplier.name!));
      if (supplier.phone != null) rows.add(('Phone', supplier.phone!));
    } else {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.brandTint,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.brandTintBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, size: 18, color: const Color(0xFF5B3DF5)),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 10),
          ...rows.map(
            (row) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SizedBox(
                    width: 92,
                    child: Text(
                      row.$1,
                      style: TextStyle(
                        fontSize: 12,
                        color: context.mutedTextColor,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      row.$2,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (action.warnings.isNotEmpty) ...<Widget>[
            const SizedBox(height: 4),
            ...action.warnings.map(
              (warning) => Text(
                warning,
                style: const TextStyle(fontSize: 12, color: Color(0xFFB54708)),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton(
                  onPressed: busy ? null : onCancel,
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: busy ? null : onConfirm,
                  child: Text(busy ? 'Saving...' : 'Confirm & save'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.listening,
    required this.soundLevel,
    required this.pulse,
    required this.onSend,
    required this.onMicTap,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final bool listening;
  final double soundLevel;
  final Animation<double> pulse;
  final VoidCallback onSend;
  final VoidCallback onMicTap;

  @override
  Widget build(BuildContext context) {
    final canType = enabled && !listening;
    final canUseMic = enabled || listening;
    final speaking = listening && soundLevel > 0.12;
    final micButton = GestureDetector(
      onTap: canUseMic ? onMicTap : null,
      child: AnimatedBuilder(
        animation: pulse,
        builder: (context, child) {
          final breathe = listening ? 0.08 + pulse.value * 0.1 : 0.0;
          final voice = speaking ? soundLevel * 0.35 : 0.0;
          final scale = 1 + breathe + voice;
          final glow = speaking
              ? 10 + soundLevel * 22
              : (listening ? 12.0 : 0.0);
          return Transform.scale(
            scale: scale,
            child: Container(
              width: listening ? 46 : 42,
              height: listening ? 46 : 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: listening
                    ? (speaking
                          ? const Color(0xFF4338CA)
                          : const Color(0xFF5B3DF5))
                    : Colors.transparent,
                shape: BoxShape.circle,
                boxShadow: listening
                    ? <BoxShadow>[
                        BoxShadow(
                          color: Color.fromRGBO(
                            91,
                            61,
                            245,
                            speaking ? 0.55 : 0.35,
                          ),
                          blurRadius: glow,
                          spreadRadius: speaking ? 2 + soundLevel * 3 : 1,
                        ),
                      ]
                    : null,
              ),
              child: child,
            ),
          );
        },
        child: Icon(
          listening ? Icons.mic : Icons.mic_none_outlined,
          size: listening ? 26 : 24,
          color: listening
              ? Colors.white
              : (canUseMic ? null : Theme.of(context).disabledColor),
        ),
      ),
    );

    return TextField(
      controller: controller,
      focusNode: focusNode,
      enabled: enabled,
      readOnly: !canType,
      minLines: 1,
      maxLines: 3,
      textInputAction: TextInputAction.send,
      onSubmitted: (_) {
        if (canType) onSend();
      },
      decoration: InputDecoration(
        hintText: listening
            ? 'Listening… tap again to send'
            : 'Ask or tap mic to dictate…',
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
        prefixIcon: Padding(
          padding: const EdgeInsets.only(left: 6, right: 4),
          child: micButton,
        ),
        prefixIconConstraints: const BoxConstraints(
          minWidth: 52,
          minHeight: 52,
        ),
        suffixIcon: Padding(
          padding: const EdgeInsets.only(left: 4, right: 6),
          child: IconButton.filled(
            tooltip: 'Send',
            onPressed: canType ? onSend : null,
            icon: const Icon(Icons.arrow_upward),
          ),
        ),
        suffixIconConstraints: const BoxConstraints(
          minWidth: 52,
          minHeight: 52,
        ),
      ),
    );
  }
}
