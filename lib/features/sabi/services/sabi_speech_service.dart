import 'dart:async';

import 'package:speech_to_text/speech_to_text.dart';

/// Speech input for Sabi.
///
/// Use [startListening]/[stopListening] for tap-to-talk dictation.
/// Use [listenForUtterance] for Gemini-style turns that end on silence.
abstract class SabiSpeechService {
  Future<bool> initialize();
  Future<void> startListening({
    void Function(String partial)? onPartial,
    void Function(double level)? onSoundLevel,

    /// Text already in the input box — kept and appended to during dictation.
    String? seedText,
  });
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
  String _lastEmitted = '';
  void Function(String partial)? _onPartial;
  void Function(double level)? _onSoundLevel;
  Timer? _holdWatchdog;
  Completer<String>? _utteranceCompleter;
  String? _localeId;

  /// Platform silence window that ends a segment; we then commit + restart
  /// so a 4s pause does not wipe earlier words.
  static const _segmentPause = Duration(seconds: 5);

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
    // Avoid duplicating when the engine repeats committed words in partial.
    if (partial.toLowerCase().startsWith(committed.toLowerCase())) {
      return partial;
    }
    return '$committed $partial';
  }

  void _emitPartial({bool allowShrink = false}) {
    final next = _combined.trim();
    if (!allowShrink &&
        _lastEmitted.isNotEmpty &&
        next.length < _lastEmitted.length &&
        !_lastEmitted.toLowerCase().startsWith(next.toLowerCase())) {
      // Keep showing the longer stable text across segment restarts / empty
      // partials so a pause never blanks the text box.
      _onPartial?.call(_lastEmitted);
      return;
    }
    if (next.isNotEmpty) _lastEmitted = next;
    _onPartial?.call(next.isEmpty ? _lastEmitted : next);
  }

  void _commitPartial() {
    final leftover = _partial.trim();
    if (leftover.isEmpty) return;
    if (_committed.trim().isEmpty) {
      _committed = leftover;
    } else if (!_committed.toLowerCase().endsWith(leftover.toLowerCase()) &&
        !leftover.toLowerCase().startsWith(_committed.toLowerCase())) {
      _committed = '${_committed.trim()} $leftover';
    } else if (leftover.toLowerCase().startsWith(_committed.toLowerCase())) {
      _committed = leftover;
    }
    _partial = '';
  }

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
  Future<void> startListening({
    void Function(String partial)? onPartial,
    void Function(double level)? onSoundLevel,
    String? seedText,
  }) async {
    if (_holding) return;
    await _ensureReady();
    _autoRestart = true;
    _holding = true;
    final seed = seedText?.trim() ?? '';
    _committed = seed;
    _partial = '';
    _lastEmitted = seed;
    _onPartial = onPartial;
    _onSoundLevel = onSoundLevel;
    if (seed.isNotEmpty) _emitPartial();
    _startHoldWatchdog();
    await _beginListenSession(pauseFor: _segmentPause);
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
    _lastEmitted = '';
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
              if (_committed.trim().isEmpty) {
                _committed = words;
              } else if (words.toLowerCase().startsWith(
                _committed.toLowerCase(),
              )) {
                _committed = words;
              } else if (!_committed.toLowerCase().endsWith(
                words.toLowerCase(),
              )) {
                _committed = '${_committed.trim()} $words';
              }
            }
            _partial = '';
          } else if (words.isNotEmpty) {
            _partial = words;
          }
          _emitPartial();
        },
        onSoundLevelChange: (level) {
          if (!_holding) return;
          _onSoundLevel?.call(level);
        },
        listenOptions: SpeechListenOptions(
          partialResults: true,
          cancelOnError: false,
          listenMode: ListenMode.dictation,
          listenFor: const Duration(minutes: 5),
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
      _commitPartial();
      _emitPartial();
      if (_speech.isListening) {
        try {
          await _speech.stop();
        } catch (_) {}
      }
      await Future<void>.delayed(const Duration(milliseconds: 220));
      if (!_holding || !_autoRestart) return;
      if (_speech.isListening) return;
      await _beginListenSession(pauseFor: _segmentPause);
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
    _onSoundLevel = null;
    if (_speech.isListening) {
      await _speech.stop();
    }
    await Future<void>.delayed(const Duration(milliseconds: 220));
    _commitPartial();
    final text = (_committed.trim().isNotEmpty ? _committed : _lastEmitted)
        .trim();
    _committed = '';
    _partial = '';
    _lastEmitted = '';
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
    _onSoundLevel = null;
    _committed = '';
    _partial = '';
    _lastEmitted = '';
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
