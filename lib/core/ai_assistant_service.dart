import 'api_client.dart';

/// AI Business Assistant -> POST v1/retailer/ai-assistant.
class AiReply {
  final String text;
  final bool showSuggestions;
  const AiReply(this.text, {this.showSuggestions = false});
}

class AiAssistantService {
  AiAssistantService._();

  static final ApiClient _api = ApiClient.instance;
  static const String _path = 'v1/retailer/ai-assistant';

  static Future<AiReply> ask(String prompt, {String page = 'Dashboard'}) async {
    final res = await _api.post(
      _path,
      body: {'prompt': prompt, 'current_page': page},
      receiveTimeout: const Duration(seconds: 60),
    );
    final d = res['data'];
    if (d is! Map) throw ApiException('Unexpected server response.');
    final text = (d['response'] ?? '').toString().trim();
    if (text.isEmpty) throw ApiException('The assistant sent an empty answer.');
    return AiReply(text, showSuggestions: d['show_suggestions'] == true);
  }
}
