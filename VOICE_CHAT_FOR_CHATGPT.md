# SabiBom Voice Chat — files for ChatGPT

## How to use
1. Paste the **Prompt** section into ChatGPT first.
2. Then paste each **FILE** block below (or upload this whole markdown).
3. Ask ChatGPT to improve UX, interrupt handling, echo prevention, and UI.

## Prompt (paste this first)

```
You are a senior Flutter + Riverpod engineer.

Improve SabiBom's Gemini-style English-only voice chat.

Stack:
- Flutter, Riverpod Notifier, go_router
- speech_to_text, flutter_tts
- Device: Android (TECNO)

Current flow:
listen → think (API) → speak (TTS) → listen

Known issues we already hit:
1. Orb interrupt while speaking caused listen/speak looping because the old speak→listen chain kept running.
2. Mic echo of TTS replies.
3. Empty silence causing nudge speech loops.
4. We removed Krio — English only.

Goals:
- Smooth continuous conversation like Gemini Live
- Reliable barge-in (tap orb while speaking)
- No double listen loops
- Strong echo suppression
- Cleaner UI / status / transcript
- Keep Riverpod + current service abstractions
- Return full rewritten Dart files, ready to paste

Constraints:
- English only
- Do not invent backend APIs; reuse sabiAssistantControllerProvider.ask / parseAction
- Keep generation-token cancellation pattern if useful
```

## File list (absolute paths)

Core voice chat:
1. `lib/features/sabi/presentation/sabi_voice_chat_screen.dart` — UI page
2. `lib/features/sabi/application/sabi_voice_chat_controller.dart` — session loop
3. `lib/features/sabi/services/sabi_speech_service.dart` — STT
4. `lib/features/sabi/services/sabi_tts_service.dart` — TTS

Related wiring:
5. `lib/features/sabi/application/sabi_providers.dart` — speech provider
6. `lib/app/router.dart` — route `/sales/sabi-voice`
7. `lib/features/sabi/presentation/sabi_navigation.dart` — opens voice route
8. `lib/features/sabi/presentation/sabi_assistant_sheet.dart` — "Voice chat" button entry

---

## FILE 1: sabi_voice_chat_screen.dart

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  var _started = false;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
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

    final orbColor = switch (voice.phase) {
      SabiVoicePhase.listening => const Color(0xFF5B3DF5),
      SabiVoicePhase.thinking => const Color(0xFF7C5CFF),
      SabiVoicePhase.speaking => const Color(0xFF2F80ED),
      _ => const Color(0xFF6B7280),
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
              Text(
                status,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                hint,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white60, fontSize: 14),
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
                AnimatedBuilder(
                  animation: _pulse,
                  builder: (context, child) {
                    final active =
                        voice.phase == SabiVoicePhase.listening ||
                        voice.phase == SabiVoicePhase.speaking;
                    final scale = active ? 1 + (_pulse.value * 0.08) : 1.0;
                    final glow = active ? 28 + (_pulse.value * 18) : 12.0;
                    return Transform.scale(
                      scale: scale,
                      child: GestureDetector(
                        onTap: () => ref
                            .read(sabiVoiceChatControllerProvider.notifier)
                            .onOrbTap(),
                        child: Container(
                          width: 168,
                          height: 168,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: <Color>[
                                orbColor.withValues(alpha: 0.95),
                                orbColor.withValues(alpha: 0.55),
                                const Color(0xFF151B2E),
                              ],
                              stops: const <double>[0.35, 0.7, 1],
                            ),
                            boxShadow: <BoxShadow>[
                              BoxShadow(
                                color: orbColor.withValues(alpha: 0.55),
                                blurRadius: glow,
                                spreadRadius: active ? 4 : 0,
                              ),
                            ],
                          ),
                          child: Icon(
                            voice.phase == SabiVoicePhase.speaking
                                ? Icons.graphic_eq_rounded
                                : Icons.mic_rounded,
                            size: 56,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    );
                  },
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
```

---

## FILE 2: sabi_voice_chat_controller.dart

```dart
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/sabi_controller.dart';
import '../application/sabi_providers.dart';
import '../domain/sabi_intent.dart';
import '../domain/sabi_message.dart';
import '../services/sabi_speech_service.dart';
import '../services/sabi_tts_service.dart';

enum SabiVoicePhase {
  idle,
  connecting,
  listening,
  thinking,
  speaking,
  ended,
}

class SabiVoiceChatState {
  const SabiVoiceChatState({
    this.phase = SabiVoicePhase.idle,
    this.partialTranscript = '',
    this.lastUserText = '',
    this.lastAssistantText = '',
    this.errorMessage,
    this.sessionActive = false,
    this.openSaleDraftQuery,
  });

  final SabiVoicePhase phase;
  final String partialTranscript;
  final String lastUserText;
  final String lastAssistantText;
  final String? errorMessage;
  final bool sessionActive;
  final String? openSaleDraftQuery;

  SabiVoiceChatState copyWith({
    SabiVoicePhase? phase,
    String? partialTranscript,
    String? lastUserText,
    String? lastAssistantText,
    String? errorMessage,
    bool clearError = false,
    bool? sessionActive,
    String? openSaleDraftQuery,
    bool clearOpenSaleDraft = false,
  }) => SabiVoiceChatState(
    phase: phase ?? this.phase,
    partialTranscript: partialTranscript ?? this.partialTranscript,
    lastUserText: lastUserText ?? this.lastUserText,
    lastAssistantText: lastAssistantText ?? this.lastAssistantText,
    errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    sessionActive: sessionActive ?? this.sessionActive,
    openSaleDraftQuery: clearOpenSaleDraft
        ? null
        : (openSaleDraftQuery ?? this.openSaleDraftQuery),
  );
}

String _normalizeSpeech(String text) {
  return text
      .toLowerCase()
      .replaceAll(RegExp(r"[^a-z0-9\s]"), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

/// True when the mic likely heard Sabi's own TTS (echo / feedback).
bool _looksLikeEcho(String heard, String spoken) {
  final a = _normalizeSpeech(heard);
  final b = _normalizeSpeech(spoken);
  if (a.isEmpty || b.isEmpty) return false;
  if (a == b) return true;
  if (a.length >= 10 && b.contains(a)) return true;
  if (b.length >= 10 && a.contains(b)) return true;

  final aWords = a.split(' ').where((w) => w.length > 2).toSet();
  final bWords = b.split(' ').where((w) => w.length > 2).toSet();
  if (aWords.isEmpty || bWords.isEmpty) return false;
  final overlap = aWords.intersection(bWords).length;
  final ratio = overlap / aWords.length;
  return overlap >= 3 && ratio >= 0.55;
}

/// Continuous English voice loop: listen → think → speak → listen.
///
/// Mic is cancelled while TTS plays. Interrupting bumps [_generation] so the
/// unfinished speak/think chain cannot start a second listen loop.
class SabiVoiceChatController extends Notifier<SabiVoiceChatState> {
  var _generation = 0;
  String? _businessId;
  String _lastSpoken = '';
  var _orbBusy = false;

  static const _echoCooldown = Duration(milliseconds: 900);
  static const _englishLocales = <String>[
    'en_US',
    'en-US',
    'en_GB',
    'en-GB',
  ];

  SabiSpeechService get _speech => ref.read(sabiSpeechServiceProvider);
  SabiTtsService get _tts => ref.read(sabiTtsServiceProvider);

  @override
  SabiVoiceChatState build() {
    ref.onDispose(() {
      _generation++;
      unawaited(_speech.cancel());
      unawaited(_tts.stop());
    });
    return const SabiVoiceChatState();
  }

  Future<void> startSession({required String businessId}) async {
    if (state.sessionActive) return;
    _businessId = businessId;
    final gen = ++_generation;
    state = state.copyWith(
      sessionActive: true,
      phase: SabiVoicePhase.connecting,
      clearError: true,
      clearOpenSaleDraft: true,
    );

    try {
      final ready = await _speech.initialize();
      if (gen != _generation) return;
      if (!ready) {
        state = state.copyWith(
          sessionActive: false,
          phase: SabiVoicePhase.ended,
          errorMessage: 'Microphone is unavailable on this device.',
        );
        return;
      }

      final localeId = await _speech.resolveLocaleId(_englishLocales);
      await _speech.setLocaleId(localeId);
      await _tts.setLanguageCode('en-US');

      await _speech.cancel();
      await _speak(
        "Hi, I'm Sabi. I'm listening — ask me about your business, sales, or stock.",
        gen,
      );
      if (gen != _generation || !state.sessionActive) return;
      await _listenTurn(gen);
    } catch (error) {
      if (gen != _generation) return;
      state = state.copyWith(
        sessionActive: false,
        phase: SabiVoicePhase.ended,
        errorMessage: '$error',
      );
    }
  }

  Future<void> endSession() async {
    _generation++;
    _orbBusy = false;
    state = state.copyWith(
      sessionActive: false,
      phase: SabiVoicePhase.ended,
      partialTranscript: '',
    );
    await _speech.cancel();
    await _tts.stop();
  }

  /// Tap while speaking to barge in; tap while listening to submit the turn.
  Future<void> onOrbTap() async {
    if (!state.sessionActive || _orbBusy) return;
    _orbBusy = true;
    try {
      switch (state.phase) {
        case SabiVoicePhase.speaking:
          // Invalidate the in-flight speak → listen chain, then start fresh.
          final gen = ++_generation;
          await _tts.stop();
          await _speech.cancel();
          if (!state.sessionActive || gen != _generation) return;
          await Future<void>.delayed(const Duration(milliseconds: 450));
          if (!state.sessionActive || gen != _generation) return;
          await _listenTurn(gen);
        case SabiVoicePhase.listening:
          final gen = _generation;
          final text = await _speech.stopListening();
          if (gen != _generation || !state.sessionActive) return;
          await _handleUserSpeech(text, gen);
        case SabiVoicePhase.thinking:
        case SabiVoicePhase.connecting:
        case SabiVoicePhase.idle:
        case SabiVoicePhase.ended:
          break;
      }
    } finally {
      _orbBusy = false;
    }
  }

  Future<void> _speak(String text, int gen) async {
    final cleaned = text.trim();
    if (cleaned.isEmpty) return;

    await _speech.cancel();
    if (gen != _generation || !state.sessionActive) return;

    state = state.copyWith(
      phase: SabiVoicePhase.speaking,
      lastAssistantText: cleaned,
      partialTranscript: '',
    );
    _lastSpoken = cleaned;

    await _tts.speak(cleaned);
    if (gen != _generation || !state.sessionActive) return;

    await Future<void>.delayed(_echoCooldown);
    if (gen != _generation || !state.sessionActive) return;
  }

  Future<void> _listenTurn(int gen) async {
    if (gen != _generation || !state.sessionActive) return;

    await _speech.cancel();
    if (gen != _generation || !state.sessionActive) return;

    state = state.copyWith(
      phase: SabiVoicePhase.listening,
      partialTranscript: '',
      clearError: true,
    );
    try {
      final text = await _speech.listenForUtterance(
        onPartial: (partial) {
          if (gen != _generation) return;
          if (_looksLikeEcho(partial, _lastSpoken)) return;
          state = state.copyWith(partialTranscript: partial);
        },
      );
      if (gen != _generation || !state.sessionActive) return;
      await _handleUserSpeech(text, gen);
    } catch (error) {
      if (gen != _generation || !state.sessionActive) return;
      state = state.copyWith(errorMessage: '$error');
      await Future<void>.delayed(const Duration(milliseconds: 600));
      if (gen != _generation || !state.sessionActive) return;
      await _listenTurn(gen);
    }
  }

  Future<void> _handleUserSpeech(String raw, int gen) async {
    var text = raw.trim();

    if (text.isNotEmpty && _looksLikeEcho(text, _lastSpoken)) {
      text = '';
    }

    // Empty / silence: keep listening quietly. Do not speak a nudge — that
    // creates a speak ↔ listen loop when the mic keeps returning empty.
    if (text.isEmpty) {
      state = state.copyWith(partialTranscript: '');
      await _listenTurn(gen);
      return;
    }

    state = state.copyWith(
      phase: SabiVoicePhase.thinking,
      lastUserText: text,
      partialTranscript: '',
    );

    await _speech.cancel();

    final businessId = _businessId;
    if (businessId == null) {
      await endSession();
      return;
    }

    if (!sabiLooksLikeDataAction(text) && sabiLooksLikeSaleDraft(text)) {
      state = state.copyWith(openSaleDraftQuery: text);
      await _speak("Okay — I'll open a sale draft for that.", gen);
      if (gen != _generation) return;
      await endSession();
      return;
    }

    final assistant = ref.read(sabiAssistantControllerProvider.notifier);
    if (sabiLooksLikeDataAction(text)) {
      await assistant.parseAction(
        businessId: businessId,
        instruction: text,
        fromVoice: false,
      );
    } else {
      await assistant.ask(
        businessId: businessId,
        question: text,
        speakReply: false,
        replyLanguage: 'en',
      );
    }
    if (gen != _generation || !state.sessionActive) return;

    final assistantState = ref.read(sabiAssistantControllerProvider);
    if (assistantState.pendingAction == 'open_sale_draft') {
      state = state.copyWith(openSaleDraftQuery: text);
      await _speak("Okay — I'll open a sale draft for that.", gen);
      if (gen != _generation) return;
      await endSession();
      return;
    }

    final reply = assistantState.errorMessage?.trim().isNotEmpty == true
        ? assistantState.errorMessage!.trim()
        : _latestAssistantText(assistantState);
    final spoken = reply.isEmpty
        ? "I'm not sure how to help with that. Try asking another way."
        : reply;

    await _speak(spoken, gen);
    if (gen != _generation || !state.sessionActive) return;

    if (assistantState.pendingSabiAction != null) {
      await _speak(
        'Please confirm or cancel that on the chat screen when you are ready.',
        gen,
      );
      await endSession();
      return;
    }

    await _listenTurn(gen);
  }

  String _latestAssistantText(SabiAssistantState assistantState) {
    for (final message in assistantState.messages.reversed) {
      if (message.author == SabiMessageAuthor.assistant) {
        final text = message.text.trim();
        final cut = text.indexOf('\n\nValue:');
        if (cut > 0) return text.substring(0, cut).trim();
        return text;
      }
    }
    return '';
  }
}

final sabiVoiceChatControllerProvider =
    NotifierProvider<SabiVoiceChatController, SabiVoiceChatState>(
      SabiVoiceChatController.new,
    );
```

---

## FILE 3: sabi_speech_service.dart

```dart
import 'dart:async';

import 'package:speech_to_text/speech_to_text.dart';

/// Speech input for Sabi.
///
/// Use [startListening]/[stopListening] for tap-to-talk dictation.
/// Use [listenForUtterance] for Gemini-style turns that end on silence.
abstract class SabiSpeechService {
  Future<bool> initialize();
  Future<void> startListening({void Function(String partial)? onPartial});
  Future<String> stopListening();
  Future<void> cancel();

  /// Listens until the platform detects end-of-speech (silence), then returns
  /// the transcript. Does not auto-restart segments.
  Future<String> listenForUtterance({
    void Function(String partial)? onPartial,
    Duration pauseFor = const Duration(seconds: 2),
  });

  /// Preferred locale for recognition (e.g. `en_US`). Null = device default.
  Future<void> setLocaleId(String? localeId);
  Future<String?> resolveLocaleId(List<String> candidates);

  bool get isAvailable;
  bool get isListening;
}

class DeviceSabiSpeechService implements SabiSpeechService {
  final SpeechToText _speech = SpeechToText();
  var _available = false;
  var _holding = false;
  var _restarting = false;
  var _autoRestart = true;
  String _committed = '';
  String _partial = '';
  void Function(String partial)? _onPartial;
  Timer? _holdWatchdog;
  Completer<String>? _utteranceCompleter;
  String? _localeId;

  @override
  bool get isAvailable => _available;

  @override
  bool get isListening => _holding || _speech.isListening;

  @override
  Future<void> setLocaleId(String? localeId) async {
    _localeId = localeId;
  }

  @override
  Future<String?> resolveLocaleId(List<String> candidates) async {
    await _ensureReady();
    try {
      final locales = await _speech.locales();
      final available = locales.map((l) => l.localeId).toList();
      String norm(String id) => id.replaceAll('-', '_').toLowerCase();
      for (final candidate in candidates) {
        final wanted = norm(candidate);
        for (final id in available) {
          if (norm(id) == wanted) return id;
        }
      }
      for (final candidate in candidates) {
        final prefix = candidate.split(RegExp(r'[-_]')).first.toLowerCase();
        for (final id in available) {
          if (id.toLowerCase().startsWith(prefix)) return id;
        }
      }
    } catch (_) {}
    return null;
  }

  String get _combined {
    final committed = _committed.trim();
    final partial = _partial.trim();
    if (committed.isEmpty) return partial;
    if (partial.isEmpty) return committed;
    return '$committed $partial';
  }

  void _emitPartial() => _onPartial?.call(_combined);

  void _attachListeners() {
    _speech.errorListener = (_) {
      if (!_holding) return;
      if (_autoRestart) {
        unawaited(_restartWhileHolding());
      } else {
        unawaited(_finishUtterance());
      }
    };
    _speech.statusListener = (status) {
      if (!_holding || _restarting) return;
      if (status == SpeechToText.doneStatus ||
          status == SpeechToText.notListeningStatus) {
        if (_autoRestart) {
          unawaited(_restartWhileHolding());
        } else {
          unawaited(_finishUtterance());
        }
      }
    };
  }

  void _startHoldWatchdog() {
    _holdWatchdog?.cancel();
    if (!_autoRestart) return;
    _holdWatchdog = Timer.periodic(const Duration(milliseconds: 350), (_) {
      if (!_holding) {
        _holdWatchdog?.cancel();
        _holdWatchdog = null;
        return;
      }
      if (_restarting || _speech.isListening) return;
      unawaited(_restartWhileHolding());
    });
  }

  void _stopHoldWatchdog() {
    _holdWatchdog?.cancel();
    _holdWatchdog = null;
  }

  @override
  Future<bool> initialize() async {
    _attachListeners();
    if (_available) return true;
    _available = await _speech.initialize(
      onError: _speech.errorListener,
      onStatus: _speech.statusListener,
    );
    _attachListeners();
    return _available;
  }

  Future<void> _ensureReady() async {
    if (!_available) {
      final ready = await initialize();
      if (!ready) {
        throw StateError(
          'Voice input is unavailable on this device. You can type your request.',
        );
      }
    } else {
      _attachListeners();
    }
  }

  @override
  Future<void> startListening({void Function(String partial)? onPartial}) async {
    if (_holding) return;
    await _ensureReady();
    _autoRestart = true;
    _holding = true;
    _committed = '';
    _partial = '';
    _onPartial = onPartial;
    _startHoldWatchdog();
    await _beginListenSession(pauseFor: const Duration(minutes: 2));
  }

  @override
  Future<String> listenForUtterance({
    void Function(String partial)? onPartial,
    Duration pauseFor = const Duration(seconds: 2),
  }) async {
    if (_holding) {
      await cancel();
    }
    await _ensureReady();
    _autoRestart = false;
    _holding = true;
    _committed = '';
    _partial = '';
    _onPartial = onPartial;
    _utteranceCompleter = Completer<String>();
    _stopHoldWatchdog();
    await _beginListenSession(pauseFor: pauseFor);

    // Safety timeout so a stuck recognizer cannot hang the voice loop.
    return Future.any<String>(<Future<String>>[
      _utteranceCompleter!.future,
      Future<String>.delayed(const Duration(seconds: 45), () async {
        if (_holding) return stopListening();
        return _combined;
      }),
    ]);
  }

  Future<void> _beginListenSession({required Duration pauseFor}) async {
    if (!_holding) return;
    if (_speech.isListening) return;

    try {
      await _speech.listen(
        onResult: (result) {
          if (!_holding) return;
          final words = result.recognizedWords.trim();
          if (result.finalResult) {
            if (words.isNotEmpty) {
              _committed = _committed.trim().isEmpty
                  ? words
                  : '${_committed.trim()} $words';
            }
            _partial = '';
          } else {
            _partial = words;
          }
          _emitPartial();
        },
        listenOptions: SpeechListenOptions(
          partialResults: true,
          cancelOnError: false,
          listenMode: ListenMode.dictation,
          listenFor: const Duration(minutes: 2),
          pauseFor: pauseFor,
          localeId: _localeId,
        ),
      );
    } catch (_) {
      if (!_holding) return;
      if (_autoRestart) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
        if (_holding && !_speech.isListening) {
          await _beginListenSession(pauseFor: pauseFor);
        }
      } else {
        await _finishUtterance();
      }
    }
  }

  Future<void> _restartWhileHolding() async {
    if (!_holding || _restarting || !_autoRestart) return;
    _restarting = true;
    try {
      await Future<void>.delayed(const Duration(milliseconds: 180));
      if (!_holding || !_autoRestart) return;
      if (_speech.isListening) return;
      final leftover = _partial.trim();
      if (leftover.isNotEmpty) {
        _committed = _committed.trim().isEmpty
            ? leftover
            : '${_committed.trim()} $leftover';
        _partial = '';
        _emitPartial();
      }
      await _beginListenSession(pauseFor: const Duration(minutes: 2));
    } finally {
      _restarting = false;
    }
  }

  Future<void> _finishUtterance() async {
    if (!_holding || _autoRestart) return;
    final text = await stopListening();
    final completer = _utteranceCompleter;
    _utteranceCompleter = null;
    if (completer != null && !completer.isCompleted) {
      completer.complete(text);
    }
  }

  @override
  Future<String> stopListening() async {
    _holding = false;
    _autoRestart = true;
    _stopHoldWatchdog();
    _onPartial = null;
    if (_speech.isListening) {
      await _speech.stop();
    }
    await Future<void>.delayed(const Duration(milliseconds: 220));
    final leftover = _partial.trim();
    if (leftover.isNotEmpty) {
      _committed = _committed.trim().isEmpty
          ? leftover
          : '${_committed.trim()} $leftover';
      _partial = '';
    }
    final text = _committed.trim();
    _committed = '';
    _partial = '';
    final completer = _utteranceCompleter;
    _utteranceCompleter = null;
    if (completer != null && !completer.isCompleted) {
      completer.complete(text);
    }
    return text;
  }

  @override
  Future<void> cancel() async {
    _holding = false;
    _autoRestart = true;
    _stopHoldWatchdog();
    _onPartial = null;
    _committed = '';
    _partial = '';
    if (_speech.isListening) {
      await _speech.cancel();
    }
    final completer = _utteranceCompleter;
    _utteranceCompleter = null;
    if (completer != null && !completer.isCompleted) {
      completer.complete('');
    }
  }
}
```

---

## FILE 4: sabi_tts_service.dart

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';

abstract class SabiTtsService {
  /// Speaks [text] and completes when playback finishes (or is stopped).
  Future<void> speak(String text);

  Future<void> stop();

  Future<void> setLanguageCode(String languageCode);

  bool get isSpeaking;
}

class DeviceSabiTtsService implements SabiTtsService {
  DeviceSabiTtsService() : _tts = FlutterTts();

  final FlutterTts _tts;
  var _ready = false;
  var _speaking = false;
  String _languageCode = 'en-US';

  @override
  bool get isSpeaking => _speaking;

  @override
  Future<void> setLanguageCode(String languageCode) async {
    final code = languageCode.trim().isEmpty ? 'en-US' : languageCode.trim();
    if (_languageCode == code && _ready) return;
    _languageCode = code;
    _ready = false;
    await _ensureReady();
  }

  Future<void> _ensureReady() async {
    if (_ready) return;
    final available = await _tts.isLanguageAvailable(_languageCode);
    final useCode =
        available == true || available == 1 ? _languageCode : 'en-US';
    await _tts.setLanguage(useCode);
    await _tts.setSpeechRate(0.48);
    await _tts.setVolume(1);
    await _tts.setPitch(1);
    await _tts.awaitSpeakCompletion(true);
    _ready = true;
  }

  @override
  Future<void> speak(String text) async {
    final cleaned = text.trim();
    if (cleaned.isEmpty) return;
    await _ensureReady();
    await _tts.stop();
    _speaking = true;
    try {
      await _tts.speak(cleaned);
    } finally {
      _speaking = false;
    }
  }

  @override
  Future<void> stop() async {
    _speaking = false;
    await _tts.stop();
  }
}

final sabiTtsServiceProvider = Provider<SabiTtsService>(
  (ref) => DeviceSabiTtsService(),
);
```

---

## FILE 5: sabi_providers.dart (speech wiring)

```dart
final sabiSpeechServiceProvider = Provider<SabiSpeechService>(
  (ref) => DeviceSabiSpeechService(),
);
```

---

## Route / entry (context only)

- Route path: `/sales/sabi-voice`
- Route name: `sabiVoiceChat`
- Builder: `SabiVoiceChatScreen`
- Entry: Ask Sabi sheet → **Voice chat** button → `SabiOpenVoiceChat` → `context.pushNamed(AppRouteNames.sabiVoiceChat)`
