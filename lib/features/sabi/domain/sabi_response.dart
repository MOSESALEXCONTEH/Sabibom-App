import 'sabi_action.dart';

class SabiResponse {
  const SabiResponse({
    required this.text,
    this.verified = false,
    this.metric,
    this.action,
    this.sabiAction,
  });

  final String text;
  final bool verified;
  final Map<String, dynamic>? metric;
  final String? action;
  final SabiAction? sabiAction;
}
