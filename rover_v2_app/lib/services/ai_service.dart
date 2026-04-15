import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:openrouter_api/openrouter_api.dart';

class AiService {
  AiService._internal();
  static final AiService instance = AiService._internal();

  final _client = OpenRouter.inference(
    key: "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",
    appId: "https://github.com/vjnaveen2005/Final-Year-Project-V2",
    appTitle: "Rover Control AI",
  );

  static const String _model = "stepfun/step-3.5-flash:free";

  /// Translates natural language into a list of MQTT instructions.
  Future<List<String>> getCommands(String userPrompt) async {
    const systemPrompt = '''
You are a robotic rover controller. Your task is to translate natural language user requests into a valid JSON array of rover commands.
Available commands:
- "forward" (continuous forward)
- "backward" (continuous backward)
- "left" (turn left in place)
- "right" (turn right in place)
- "stop" (halt all movement)
- "move:<number>" (e.g., "move:20" - move forward exactly <number> cm)
- "speed:<number>" (e.g., "speed:150" - set PWM speed 50-255)

If the user says "go straight" or "move forward" without a distance, use "forward".
If the user specifies a distance (e.g., "move forward 20cm"), use "move:20".

IMPORTANT: Return ONLY a valid JSON list of strings. No explanation.
Example Input: "go straight for 30 and then turn right"
Example Output: ["move:30", "right"]
''';

    try {
      final response = await _client.getCompletion(
        modelId: _model,
        messages: [
          LlmMessage.system(systemPrompt),
          LlmMessage.user(LlmMessageContent.text(userPrompt)),
        ],
      );

      if (response.choices.isNotEmpty) {
        final content = response.choices.first.content.trim();
        debugPrint('[AI] Raw content: $content');

        // Extract JSON array if AI adds triple backticks or text
        final jsonMatch = RegExp(r'\[.*\]', dotAll: true).stringMatch(content);
        if (jsonMatch != null) {
          final dynamic decoded = jsonDecode(jsonMatch);
          if (decoded is List) {
            return decoded.map((e) => e.toString()).toList();
          } else if (decoded is Map) {
            // Check for common keys like "commands" or "sequence" if AI wraps the list
            final possibleList = decoded['commands'] ?? decoded['sequence'] ?? decoded['actions'];
            if (possibleList is List) {
              return possibleList.map((e) => e.toString()).toList();
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[AI] Error: $e');
    }
    return [];
  }
}
