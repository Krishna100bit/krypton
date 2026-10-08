import 'api_key_store.dart';
import 'groq_key_store.dart';

/// Central store for LLM keys (summaries, recaps, Q&A).
/// Prefers Groq key (fast, high context, free tier), falls back to OpenAI.
class LlmKeyStore {
  static Future<String> readKey({bool refresh = false}) async {
    final groq = (await GroqKeyStore.read(refresh: refresh)).trim();
    if (groq.isNotEmpty) {
      return groq;
    }
    return (await ApiKeyStore.read(refresh: refresh)).trim();
  }
}
