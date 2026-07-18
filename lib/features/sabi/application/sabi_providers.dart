import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/placeholder_sabi_assistant_service.dart';
import '../data/sabi_assistant_service.dart';

final sabiAssistantServiceProvider = Provider<SabiAssistantService>(
  (ref) => PlaceholderSabiAssistantService(),
);
