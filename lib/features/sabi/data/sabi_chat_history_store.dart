import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/sabi_message.dart';

/// Local persistence for Sabi chat history (per signed-in user).
class SabiChatHistoryStore {
  SabiChatHistoryStore({FirebaseAuth? auth}) : _auth = auth ?? FirebaseAuth.instance;

  final FirebaseAuth _auth;
  static const _maxMessages = 120;

  String get _key {
    final uid = _auth.currentUser?.uid ?? 'guest';
    return 'sabi_chat_history_v1_$uid';
  }

  Future<List<SabiMessage>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return const <SabiMessage>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const <SabiMessage>[];
      return decoded
          .whereType<Map>()
          .map((item) => SabiMessage.fromJson(Map<String, dynamic>.from(item)))
          .where((message) => message.text.trim().isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return const <SabiMessage>[];
    }
  }

  Future<void> save(List<SabiMessage> messages) async {
    final prefs = await SharedPreferences.getInstance();
    final trimmed = messages.length > _maxMessages
        ? messages.sublist(messages.length - _maxMessages)
        : messages;
    final payload = jsonEncode(
      trimmed.map((message) => message.toJson()).toList(growable: false),
    );
    await prefs.setString(_key, payload);
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
