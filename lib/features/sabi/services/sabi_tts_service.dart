import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';

abstract class SabiTtsService {
  /// Speaks [text] and completes when playback finishes (or is stopped).
  Future<void> speak(String text);

  Future<void> stop();

  Future<void> setLanguageCode(String languageCode);

  bool get isSpeaking;
}

/// Device TTS tuned to sound like a calm, male-presenting assistant voice
/// (similar in tone to Google Gemini's voice chat).
///
/// Strategy for picking a male voice, in order of preference:
/// 1. A device voice that explicitly reports `gender: male` (iOS/macOS).
/// 2. A device voice whose name is tagged male by the platform (some Android
///    TTS engines label voices e.g. `en-us-x-iol-local#male`).
/// 3. Fallback: keep the platform's default voice but lower the pitch
///    slightly so it reads as a deeper, more masculine timbre.
class DeviceSabiTtsService implements SabiTtsService {
  DeviceSabiTtsService() : _tts = FlutterTts();

  final FlutterTts _tts;
  var _ready = false;
  var _speaking = false;
  var _usingExplicitMaleVoice = false;
  String _languageCode = 'en-US';

  /// Slightly slower than "normal" reads calmer and more deliberate, closer
  /// to Gemini's conversational pace, without sounding sluggish.
  static const double _speechRate = 0.5;

  /// Pitch used when we found an explicit male voice (keep natural).
  static const double _naturalPitch = 1.0;

  /// Pitch used when no explicit male voice is available on-device — a
  /// lower pitch reads as a deeper, more masculine voice.
  static const double _fallbackMalePitch = 0.82;

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
    await _selectMaleVoice(useCode);
    await _tts.setSpeechRate(_speechRate);
    await _tts.setVolume(1);
    await _tts.setPitch(
      _usingExplicitMaleVoice ? _naturalPitch : _fallbackMalePitch,
    );
    await _tts.awaitSpeakCompletion(true);
    _ready = true;
  }

  /// Looks through the device's installed voices for [languageCode] and
  /// selects a male-presenting one if one exists. Safe to call on any
  /// platform — failures are swallowed and just fall back to pitch tuning.
  Future<void> _selectMaleVoice(String languageCode) async {
    _usingExplicitMaleVoice = false;
    try {
      final dynamic raw = await _tts.getVoices;
      if (raw is! List) return;

      final voices = <Map<String, String>>[];
      for (final entry in raw) {
        if (entry is Map) {
          voices.add(
            entry.map(
              (key, value) => MapEntry('$key', value?.toString() ?? ''),
            ),
          );
        }
      }
      if (voices.isEmpty) return;

      final languagePrefix = languageCode
          .split(RegExp(r'[-_]'))
          .first
          .toLowerCase();
      final candidates = voices.where((voice) {
        final locale = (voice['locale'] ?? '').toLowerCase();
        return locale.startsWith(languagePrefix);
      }).toList();
      if (candidates.isEmpty) return;

      Map<String, String>? male;

      // 1) Explicit gender metadata (iOS/macOS report this reliably).
      for (final voice in candidates) {
        if ((voice['gender'] ?? '').toLowerCase() == 'male') {
          male = voice;
          break;
        }
      }

      // 2) Name-based hint some Android TTS engines expose (e.g. contains
      // "male" but not "female").
      male ??= _firstWhere(candidates, (voice) {
        final name = (voice['name'] ?? '').toLowerCase();
        return name.contains('male') && !name.contains('female');
      });

      if (male == null) return;

      final name = male['name'];
      if (name == null || name.isEmpty) return;

      final result = await _tts.setVoice(<String, String>{
        'name': name,
        'locale': male['locale'] ?? languageCode,
      });
      _usingExplicitMaleVoice = result == 1 || result == '1' || result == true;
    } catch (_) {
      _usingExplicitMaleVoice = false;
    }
  }

  Map<String, String>? _firstWhere(
    List<Map<String, String>> items,
    bool Function(Map<String, String>) test,
  ) {
    for (final item in items) {
      if (test(item)) return item;
    }
    return null;
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
