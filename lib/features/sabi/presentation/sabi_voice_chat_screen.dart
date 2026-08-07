import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_motion.dart';
import '../../dashboard/application/dashboard_providers.dart';
import '../application/sabi_voice_chat_controller.dart';
import 'sabi_navigation.dart';

/// Full-screen continuous English voice conversation with Sabi.
class SabiVoiceChatScreen extends ConsumerStatefulWidget {
  const SabiVoiceChatScreen({super.key});

  @override
  ConsumerState<SabiVoiceChatScreen> createState() =>
      _SabiVoiceChatScreenState();
}

class _SabiVoiceChatScreenState extends ConsumerState<SabiVoiceChatScreen>
    with TickerProviderStateMixin {
  late final AnimationController _pulse;
  late final AnimationController _spin;
  var _started = false;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: AppMotion.emphasized * 5,
    )..repeat(reverse: true);
    _spin = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 9),
    )..repeat();
  }

  @override
  void dispose() {
    _pulse.dispose();
    _spin.dispose();
    super.dispose();
  }

  Future<void> _startTalking() async {
    if (_started || !mounted) return;
    final active = ref.read(activeBusinessProvider).asData?.value;
    if (active is! ActiveBusinessData) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a business to talk with Sabi.')),
      );
      context.pop();
      return;
    }
    setState(() => _started = true);
    await ref.read(sabiVoiceChatControllerProvider.notifier).startSession(
          businessId: active.business.businessId,
        );
  }

  Future<void> _close() async {
    final draft = ref.read(sabiVoiceChatControllerProvider).openSaleDraftQuery;
    await ref.read(sabiVoiceChatControllerProvider.notifier).endSession();
    if (!mounted) return;
    context.pop();
    if (draft != null && draft.trim().isNotEmpty && mounted) {
      await SabiSaleDraftNavigator.open(context, query: draft);
    }
  }

  @override
  Widget build(BuildContext context) {
    final voice = ref.watch(sabiVoiceChatControllerProvider);

    ref.listen<SabiVoiceChatState>(sabiVoiceChatControllerProvider, (
      previous,
      next,
    ) {
      if (next.phase == SabiVoicePhase.ended &&
          next.openSaleDraftQuery != null &&
          previous?.phase != SabiVoicePhase.ended) {
        final query = next.openSaleDraftQuery!;
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (!mounted) return;
          context.pop();
          await SabiSaleDraftNavigator.open(context, query: query);
        });
      }
    });

    final status = !_started
        ? 'Voice chat'
        : switch (voice.phase) {
            SabiVoicePhase.idle || SabiVoicePhase.connecting => 'Connecting…',
            SabiVoicePhase.listening => 'Listening…',
            SabiVoicePhase.thinking => 'Thinking…',
            SabiVoicePhase.speaking => 'Sabi is speaking…',
            SabiVoicePhase.ended => 'Call ended',
          };

    final hint = !_started
        ? 'Talk with Sabi about your business'
        : switch (voice.phase) {
            SabiVoicePhase.listening => 'Tap the orb when you finish speaking',
            SabiVoicePhase.speaking => 'Tap the orb to interrupt',
            SabiVoicePhase.thinking => 'One moment',
            _ => 'Talk with Sabi like Gemini voice chat',
          };

    final orbColors = switch (voice.phase) {
      SabiVoicePhase.listening => const <Color>[
        Color(0xFF6C4CFF),
        Color(0xFF3EC6FF),
      ],
      SabiVoicePhase.thinking => const <Color>[
        Color(0xFF8A5CFF),
        Color(0xFFB16CFF),
      ],
      SabiVoicePhase.speaking => const <Color>[
        Color(0xFF3E8DFF),
        Color(0xFF4FE0C4),
      ],
      _ => const <Color>[Color(0xFF6B7280), Color(0xFF4B5563)],
    };

    return Scaffold(
      backgroundColor: const Color(0xFF0B1020),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            children: <Widget>[
              Row(
                children: <Widget>[
                  IconButton(
                    tooltip: 'Close',
                    onPressed: _close,
                    icon: const Icon(Icons.close, color: Colors.white70),
                  ),
                  const Expanded(
                    child: Text(
                      'Sabi Voice',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
              const Spacer(),
              AnimatedSwitcher(
                duration: AppMotion.standard,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.12),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                ),
                child: Row(
                  key: ValueKey<String>(status),
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    if (_started &&
                        (voice.phase == SabiVoicePhase.connecting ||
                            voice.phase == SabiVoicePhase.thinking ||
                            voice.phase == SabiVoicePhase.idle)) ...<Widget>[
                      const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white70,
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Flexible(
                      child: Text(
                        status,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              AnimatedSwitcher(
                duration: AppMotion.standard,
                child: Text(
                  hint,
                  key: ValueKey<String>(hint),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white60, fontSize: 14),
                ),
              ),
              const SizedBox(height: 36),
              if (!_started)
                FilledButton.icon(
                  onPressed: _startTalking,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF5B3DF5),
                    minimumSize: const Size(220, 52),
                  ),
                  icon: const Icon(Icons.graphic_eq_rounded),
                  label: const Text('Start chat'),
                )
              else
                _GeminiOrb(
                  phase: voice.phase,
                  colors: orbColors,
                  pulse: _pulse,
                  spin: _spin,
                  onTap: () => ref
                      .read(sabiVoiceChatControllerProvider.notifier)
                      .onOrbTap(),
                ),
              const SizedBox(height: 36),
              _TranscriptCard(
                userText: voice.partialTranscript.isNotEmpty
                    ? voice.partialTranscript
                    : voice.lastUserText,
                assistantText: voice.lastAssistantText,
                showPartial: voice.partialTranscript.isNotEmpty,
              ),
              if (voice.errorMessage != null) ...<Widget>[
                const SizedBox(height: 12),
                Text(
                  voice.errorMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFFFFB4A8)),
                ),
              ],
              const Spacer(),
              if (_started)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    _RoundAction(
                      color: const Color(0xFFE11D48),
                      icon: Icons.call_end_rounded,
                      label: 'End',
                      onTap: _close,
                    ),
                    const SizedBox(width: 28),
                    _RoundAction(
                      color: const Color(0xFF5B3DF5),
                      icon: Icons.chat_bubble_outline_rounded,
                      label: 'Chat',
                      onTap: () async {
                        await ref
                            .read(sabiVoiceChatControllerProvider.notifier)
                            .endSession();
                        if (!context.mounted) return;
                        context.pop();
                      },
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Gemini Live–style animated orb: a soft, layered blob that breathes while
/// idle/listening, pulses faster while thinking, and ripples outward while
/// Sabi speaks. Tap to interrupt (speaking) or submit the turn (listening).
class _GeminiOrb extends StatelessWidget {
  const _GeminiOrb({
    required this.phase,
    required this.colors,
    required this.pulse,
    required this.spin,
    required this.onTap,
  });

  final SabiVoicePhase phase;
  final List<Color> colors;
  final AnimationController pulse;
  final AnimationController spin;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final active =
        phase == SabiVoicePhase.listening ||
        phase == SabiVoicePhase.speaking ||
        phase == SabiVoicePhase.thinking;
    final speaking = phase == SabiVoicePhase.speaking;
    final thinking = phase == SabiVoicePhase.thinking;

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 220,
        height: 220,
        child: AnimatedBuilder(
          animation: Listenable.merge(<Listenable>[pulse, spin]),
          builder: (context, child) {
            final breathe = CurvedAnimation(
              parent: pulse,
              curve: Curves.easeInOutSine,
            ).value;
            final speed = thinking ? 2.4 : 1.0;
            final scale = active ? 1 + (breathe * 0.09 * speed) : 1.0;
            final ringScale = active ? 1.12 + (breathe * 0.16) : 1.0;
            final glow = active ? 26 + (breathe * 22) : 10.0;
            final rotation = spin.value * 2 * 3.14159265;

            return Stack(
              alignment: Alignment.center,
              children: <Widget>[
                // Outer ripple ring — only visible while active.
                if (active)
                  Opacity(
                    opacity: (0.25 + breathe * 0.2).clamp(0.0, 0.6),
                    child: Transform.scale(
                      scale: ringScale,
                      child: Container(
                        width: 176,
                        height: 176,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: colors.last.withValues(alpha: 0.8),
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                  ),
                // Core orb: rotating dual-tone gradient for a "living" blob
                // feel, similar to Gemini's live voice indicator.
                Transform.scale(
                  scale: scale,
                  child: Transform.rotate(
                    angle: rotation,
                    child: Container(
                      width: 168,
                      height: 168,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: SweepGradient(
                          colors: <Color>[
                            colors.first,
                            colors.last,
                            colors.first,
                          ],
                          stops: const <double>[0, 0.55, 1],
                        ),
                        boxShadow: <BoxShadow>[
                          BoxShadow(
                            color: colors.first.withValues(alpha: 0.55),
                            blurRadius: glow,
                            spreadRadius: active ? 4 : 0,
                          ),
                        ],
                      ),
                      child: Center(
                        child: Container(
                          width: 132,
                          height: 132,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: <Color>[
                                colors.first.withValues(alpha: 0.95),
                                colors.last.withValues(alpha: 0.65),
                                const Color(0xFF151B2E),
                              ],
                              stops: const <double>[0.2, 0.68, 1],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Icon(
                  speaking ? Icons.graphic_eq_rounded : Icons.mic_rounded,
                  size: 52,
                  color: Colors.white,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _TranscriptCard extends StatelessWidget {
  const _TranscriptCard({
    required this.userText,
    required this.assistantText,
    required this.showPartial,
  });

  final String userText;
  final String assistantText;
  final bool showPartial;

  @override
  Widget build(BuildContext context) {
    if (userText.trim().isEmpty && assistantText.trim().isEmpty) {
      return const SizedBox(height: 96);
    }
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 96, maxHeight: 160),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white12),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (userText.trim().isNotEmpty) ...<Widget>[
              Text(
                showPartial ? 'You (speaking)' : 'You',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.55),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                userText,
                style: const TextStyle(color: Colors.white, height: 1.35),
              ),
            ],
            if (assistantText.trim().isNotEmpty) ...<Widget>[
              if (userText.trim().isNotEmpty) const SizedBox(height: 12),
              Text(
                'Sabi',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.55),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                assistantText,
                maxLines: 5,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, height: 1.35),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({
    required this.color,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final Color color;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Material(
          color: color,
          shape: const CircleBorder(),
          elevation: 6,
          shadowColor: color.withValues(alpha: 0.5),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: 64,
              height: 64,
              child: Icon(icon, color: Colors.white, size: 28),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(color: Colors.white70)),
      ],
    );
  }
}
