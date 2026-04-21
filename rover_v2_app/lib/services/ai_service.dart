import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:openrouter_api/openrouter_api.dart';
import '../models/map_model.dart';
import '../algorithms/astar.dart';

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
  /// 
  /// Supports:
  /// - Place navigation: "go to Room A" → uses pathfinding to navigate to a named place
  /// - Distance movement: "move:30" (30cm forward), "back:20" (20cm backward)
  /// - Turns: "left", "right", "turn left", "turn right"
  /// - Continuous movement: "forward", "backward", "stop"
  /// - Speed control: "speed:150" (PWM value 50-255)
  Future<List<String>> getCommands(String userPrompt, {List<Place>? places, int? startRow, int? startCol, RoverGrid? grid, double cellSizeCm = 30.0}) async {
    final normalized = userPrompt.toLowerCase().trim();
    debugPrint('[AI] Processing: $normalized');
    
    // Check if user wants to navigate to a named place
    if (places != null && places.isNotEmpty && _isPlaceNavigation(normalized)) {
      return _handlePlaceNavigation(normalized, places, startRow, startCol, grid, cellSizeCm);
    }
    
    // Default: use AI to parse commands
    const systemPrompt = '''
You are a robotic rover controller. Translate natural language into MQTT commands.

DIRECTION MAPPING (CRITICAL - follow exactly):
- Forwards/forward/move forward/go straight = move forward = use "move:X"
- Backwards/backward/move backward/go back = move backward = use "back:X"
- Turn right/rotate right = face right = use "right90"
- Turn left/rotate left = face left = use "left90"
- Move right/go right = physically move right side = use "right:cm"
- Move left/go left = physically move left side = use "left:cm"

AVAILABLE COMMANDS:
- "move:X" - move forward X centimeters (X is a number)
- "back:X" - move backward X centimeters (X is a number) 
- "right:X" - move right X centimeters
- "left:X" - move left X centimeters
- "right90" - turn right 90 degrees
- "left90" - turn left 90 degrees
- "forward" - move forward continuously
- "backward" - move backward continuously
- "right" - turn right continuously
- "left" - turn left continuously
- "stop" - halt all movement

MAPPING EXAMPLES (IMPORTANT):
- "go forward 30cm" / "move forward 30cm" → ["move:30"]
- "go straight 30cm" → ["move:30"]
- "go backwards 20cm" / "go back 20cm" → ["back:20"]
- "turn right" / "rotate right" → ["right90"]
- "turn left" / "rotate left" → ["left90"]
- "move right 30cm" → ["right:30"]
- "move left 30cm" → ["left:30"]
- "go to Room A" → ["navigate:Room A"]

Respond ONLY with a valid JSON array of strings.
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

  bool _isPlaceNavigation(String text) {
    final patterns = ['go to', 'navigate to', 'move to', 'go to the', 'walk to'];
    for (final p in patterns) {
      if (text.contains(p)) return true;
    }
    return false;
  }

  List<String> _handlePlaceNavigation(
    String text,
    List<Place> places,
    int? startRow,
    int? startCol,
    RoverGrid? grid,
    double cellSizeCm,
  ) {
    // Find which place the user wants to go to
    Place? target;
    for (final p in places) {
      final nameLower = p.name.toLowerCase();
      if (text.contains(nameLower)) {
        target = p;
        break;
      }
    }

    // If no exact match, try to find a partial match
    if (target == null) {
      for (final p in places) {
        final nameLower = p.name.toLowerCase();
        for (final word in text.split(' ')) {
          if (word.length > 2 && nameLower.contains(word)) {
            target = p;
            break;
          }
        }
        if (target != null) break;
      }
    }

    if (target == null) {
      // No matching place found - return empty to trigger error message
      return [];
    }

    // If we don't have grid/start info, return navigate command with just the place name
    if (grid == null || startRow == null || startCol == null) {
      return ['navigate:${target.name}'];
    }

    // Find path from start to target
    final path = AStarPathfinder.findPath(
      grid: grid,
      startRow: startRow,
      startCol: startCol,
      goalRow: target.row,
      goalCol: target.col,
    );

    if (path == null || path.isEmpty) {
      return ['error:No path found to ${target.name}'];
    }

    // Convert path to commands
    final commands = AStarPathfinder.pathToCommands(
      path: path,
      startDirection: 0, // Default to north
      cellSizeCm: cellSizeCm,
    );

    if (commands.isEmpty) {
      return ['error:Already at ${target.name}'];
    }

    return commands;
  }
}
