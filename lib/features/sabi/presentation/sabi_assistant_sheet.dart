import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../dashboard/application/dashboard_providers.dart';
import '../application/sabi_controller.dart';
import 'widgets/sabi_message_bubble.dart';
import 'widgets/sabi_prompt_chip.dart';

const _suggestedPrompts = <String>[
  'How much did I sell today?',
  'Which products are running low?',
  'Who owes me money?',
  'Show this month\'s expenses.',
];

Future<void> showSabiAssistantSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const SabiAssistantSheet(),
  );
}

class SabiAssistantSheet extends ConsumerStatefulWidget {
  const SabiAssistantSheet({super.key});

  @override
  ConsumerState<SabiAssistantSheet> createState() => _SabiAssistantSheetState();
}

class _SabiAssistantSheetState extends ConsumerState<SabiAssistantSheet> {
  final _inputController = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _inputController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submit(String? businessId) {
    final question = _inputController.text;
    if (businessId == null || businessId.trim().isEmpty) return;
    _inputController.clear();
    ref
        .read(sabiAssistantControllerProvider.notifier)
        .ask(businessId: businessId, question: question);
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

    return FractionallySizedBox(
      heightFactor: 0.76,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: Color(0xFFFCFBFF),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 12, 20, 16 + bottomInset),
            child: Column(
              children: <Widget>[
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD7D1E8),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                const SizedBox(height: 20),
                const _SheetHeader(),
                const SizedBox(height: 20),
                if (isNoBusiness)
                  _NoBusinessContent(
                    onSetUp: () {
                      Navigator.of(context).pop();
                      context.push(AppRoutes.businessSetup);
                    },
                  )
                else ...<Widget>[
                  Expanded(
                    child: ListView(
                      children: <Widget>[
                        if (assistant.messages.isEmpty) ...<Widget>[
                          const Text(
                            'Try asking',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _suggestedPrompts
                                .map(
                                  (prompt) => SabiPromptChip(
                                    label: prompt,
                                    onPressed: assistant.isLoading
                                        ? () {}
                                        : () {
                                            _inputController.text = prompt;
                                            _submit(businessId);
                                          },
                                  ),
                                )
                                .toList(),
                          ),
                          const SizedBox(height: 24),
                        ],
                        ...assistant.messages.map(
                          (message) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: SabiMessageBubble(message: message),
                          ),
                        ),
                        if (assistant.isLoading)
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
                              style: const TextStyle(color: Color(0xFFB42318)),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _InputBar(
                    controller: _inputController,
                    focusNode: _focusNode,
                    enabled: businessId != null && !assistant.isLoading,
                    onSend: () => _submit(businessId),
                    onVoice: () => ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Voice input will be connected later.'),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SheetHeader extends StatelessWidget {
  const _SheetHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: Color(0xFFF0ECFF),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.auto_awesome, color: Color(0xFF5B3DF5)),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Hi, I\'m Sabi \u{1F44B}',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              SizedBox(height: 3),
              Text('What would you like to know about your business?'),
            ],
          ),
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

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.onSend,
    required this.onVoice,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final VoidCallback onSend;
  final VoidCallback onVoice;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            enabled: enabled,
            minLines: 1,
            maxLines: 3,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => onSend(),
            decoration: const InputDecoration(
              hintText: 'Ask Sabi anything...',
              isDense: true,
            ),
          ),
        ),
        IconButton(
          tooltip: 'Voice input',
          onPressed: onVoice,
          icon: const Icon(Icons.mic_none_outlined),
        ),
        IconButton.filled(
          tooltip: 'Send',
          onPressed: enabled ? onSend : null,
          icon: const Icon(Icons.arrow_upward),
        ),
      ],
    );
  }
}
