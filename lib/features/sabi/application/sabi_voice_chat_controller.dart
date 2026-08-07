import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/sabi_controller.dart';
import '../application/sabi_providers.dart';
import '../domain/sabi_intent.dart';
import '../domain/sabi_message.dart';
import '../services/sabi_speech_service.dart';
import '../services/sabi_tts_service.dart';

enum SabiVoicePhase { idle, connecting, listening, thinking, speaking, ended }

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
  static const _englishLocales = <String>['en_US', 'en-US', 'en_GB', 'en-GB'];

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

    final clarification = sabiClarificationFor(text);
    if (clarification == null &&
        !sabiLooksLikeDataAction(text) &&
        sabiLooksLikeSaleDraft(text)) {
      ref
          .read(sabiAssistantControllerProvider.notifier)
          .cancelPendingClarificationQuietly();
      state = state.copyWith(openSaleDraftQuery: text);
      await _speak("Okay — I'll open a sale draft for that.", gen);
      if (gen != _generation) return;
      await endSession();
      return;
    }

    final assistant = ref.read(sabiAssistantControllerProvider.notifier);
    final hasPendingClarification =
        ref.read(sabiAssistantControllerProvider).pendingClarificationIntent !=
        null;
    if (sabiLooksLikeDataAction(text) ||
        clarification != null ||
        hasPendingClarification) {
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
