import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/cloud_sabi_assistant_service.dart';
import '../data/firebase_sabi_repository.dart';
import '../data/sabi_assistant_service.dart';
import '../data/sabi_chat_history_store.dart';
import '../services/sabi_speech_service.dart';

final sabiAssistantServiceProvider = Provider<SabiAssistantService>(
  (ref) => CloudSabiAssistantService(),
);

final sabiRepositoryProvider = Provider<SabiRepository>(
  (ref) => SabiRepository(),
);

final sabiSpeechServiceProvider = Provider<SabiSpeechService>(
  (ref) => DeviceSabiSpeechService(),
);

final sabiChatHistoryStoreProvider = Provider<SabiChatHistoryStore>(
  (ref) => SabiChatHistoryStore(),
);