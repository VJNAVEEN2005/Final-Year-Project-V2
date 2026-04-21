import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/rover_theme.dart';
import '../services/mqtt_service.dart';
import '../services/ai_service.dart';
import '../services/voice_service.dart';
import '../providers/map_provider.dart';
import '../providers/navigation_provider.dart';

class ChatMessage {
  final String text;
  final bool isUser;
  final bool isSystem;
  final bool isThinking;

  ChatMessage({
    required this.text,
    required this.isUser,
    this.isSystem = false,
    this.isThinking = false,
  });
}

class AiAssistantScreen extends StatefulWidget {
  const AiAssistantScreen({super.key});

  @override
  State<AiAssistantScreen> createState() => _AiAssistantScreenState();
}

class _AiAssistantScreenState extends State<AiAssistantScreen> with TickerProviderStateMixin {
  final MqttService _mqtt = MqttService.instance;
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  bool _isVoiceActive = false;
  bool _isListening = false;
  bool _isAiThinking = false;
  String _voiceResultText = "";
  List<ChatMessage> _messages = [];
  List<String> _pendingAiCommands = [];
  String? _currentlyExecuting;
  StreamSubscription? _doneSub;
  StreamSubscription<bool>? _connSub;
  bool _isConnected = false;

  @override
  void initState() {
    super.initState();
    _connSub = _mqtt.connectionStream.listen((connected) {
      if (mounted) setState(() => _isConnected = connected);
    });
    _addWelcomeMessage();
  }

  void _addWelcomeMessage() {
    _messages.add(ChatMessage(
      text: "Hello! I'm your Rover AI Assistant.\n\nYou can:\n• Type commands below\n• Tap the mic for voice\n• Ask to navigate to places\n• Control rover movements",
      isUser: false,
      isSystem: true,
    ));
  }

  Future<void> _handleSubmit(String text) async {
    if (text.trim().isEmpty) return;
    
    final userText = text.trim();
    _textController.clear();
    
    setState(() {
      _messages.add(ChatMessage(text: userText, isUser: true));
      _messages.add(ChatMessage(text: "Thinking...", isUser: false, isSystem: true, isThinking: true));
    });
    _scrollToBottom();

    await _processAiInput(userText);
  }

  Future<void> _handleVoiceMicTap() async {
    if (_isVoiceActive) {
      if (_isListening) {
        VoiceService.instance.stopListening();
        setState(() => _isListening = false);
      } else {
        _restartListening();
      }
      return;
    }

    final ok = await VoiceService.instance.init();
    if (!ok) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not initialize voice services')),
        );
      }
      return;
    }

    setState(() {
      _isVoiceActive = true;
      _isListening = true;
    });

    _addSystemMessage("Listening for command...");

    VoiceService.instance.startListening((text) {
      if (mounted && text.isNotEmpty) {
        setState(() {
          _isListening = false;
          _isAiThinking = true;
          _voiceResultText = text;
        });
        _handleSubmit(text);
      }
    });
  }

  Future<void> _restartListening() async {
    if (!_isVoiceActive || !_isListening) return;

    setState(() {
      _isListening = true;
    });

    VoiceService.instance.startListening((text) {
      if (mounted && text.isNotEmpty) {
        setState(() {
          _isListening = false;
          _isAiThinking = true;
          _voiceResultText = text;
        });
        _handleSubmit(text);
      }
    });
  }

  void _addSystemMessage(String text) {
    setState(() {
      _messages.add(ChatMessage(text: text, isUser: false, isSystem: true));
    });
    _scrollToBottom();
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _processAiInput(String inputText) async {
    if (inputText.isEmpty) {
      setState(() => _isVoiceActive = false);
      return;
    }

    final mapProvider = context.read<MapProvider>();
    final navProvider = NavigationProvider.instance;

    final currentMap = mapProvider.currentMap;
    final startRow = currentMap?.startRow ?? navProvider.currentRow;
    final startCol = currentMap?.startCol ?? navProvider.currentCol;
    final places = currentMap?.places ?? [];
    final grid = currentMap?.grid;
    final cellSize = currentMap?.cellSizeCm ?? 30.0;

    final commands = await AiService.instance.getCommands(
      inputText,
      places: places,
      startRow: startRow,
      startCol: startCol,
      grid: grid,
      cellSizeCm: cellSize,
    );
    if (!mounted) return;

    // Remove thinking message and add response
    setState(() {
      _messages.removeWhere((m) => m.isThinking);
      _isAiThinking = false;
    });

    if (commands.isEmpty) {
      _addSystemMessage("I didn't understand that command. Try something like 'move forward 30cm' or 'go to Room A'.");
      return;
    }

    // Check for error responses
    for (final cmd in commands) {
      if (cmd.startsWith('error:')) {
        _addSystemMessage(cmd.substring(6));
        return;
      }
    }

    setState(() {
      _pendingAiCommands = commands;
    });

    final confirmText = "Executing: ${commands.join(' → ')}";
    _addSystemMessage(confirmText);
    VoiceService.instance.speak(confirmText);

    _executeAiSequence(
      commands,
      startRow: navProvider.currentRow,
      startCol: navProvider.currentCol,
      cellSize: cellSize,
    );
  }

  Future<void> _executeAiSequence(List<String> commands, {int? startRow, int? startCol, double cellSize = 30.0}) async {
    int curRow = startRow ?? 0;
    int curCol = startCol ?? 0;
    int curDir = 0;

    for (final cmd in commands) {
      if (!mounted) break;

      if (cmd.startsWith('error:')) {
        setState(() => _currentlyExecuting = cmd);
        _addSystemMessage(cmd.substring(6));
        continue;
      }

      setState(() => _currentlyExecuting = cmd);
      _mqtt.publish(cmd);

      if (cmd.startsWith('move:')) {
        final dist = double.tryParse(cmd.substring(5)) ?? 10.0;
        final completer = Completer<void>();
        _doneSub = _mqtt.doneStream.listen((_) {
          if (!completer.isCompleted) completer.complete();
        });

        await completer.future.timeout(
          Duration(seconds: (dist / 5).round() + 3),
          onTimeout: () => debugPrint('[AI] Move timeout'),
        );
        _doneSub?.cancel();

        final cellsToMove = (dist / cellSize).round();
        _movePosition(curDir, cellsToMove, curRow, curCol, (r, c) {
          curRow = r;
          curCol = c;
        });

      } else if (cmd.startsWith('back:')) {
        final dist = double.tryParse(cmd.substring(5)) ?? 10.0;
        final completer = Completer<void>();
        _doneSub = _mqtt.doneStream.listen((_) {
          if (!completer.isCompleted) completer.complete();
        });

        await completer.future.timeout(
          Duration(seconds: (dist / 5).round() + 3),
          onTimeout: () => debugPrint('[AI] Back timeout'),
        );
        _doneSub?.cancel();

        final cellsToMove = (dist / cellSize).round();
        _movePosition(curDir, -cellsToMove, curRow, curCol, (r, c) {
          curRow = r;
          curCol = c;
        });

      } else if (cmd == 'left90') {
        curDir = (curDir - 1 + 4) % 4;
        final completer = Completer<void>();
        _doneSub = _mqtt.doneStream.listen((_) {
          if (!completer.isCompleted) completer.complete();
        });
        await Future.any([
          completer.future,
          Future.delayed(const Duration(milliseconds: 2000)),
        ]);
        _doneSub?.cancel();

      } else if (cmd == 'right90') {
        curDir = (curDir + 1) % 4;
        final completer = Completer<void>();
        _doneSub = _mqtt.doneStream.listen((_) {
          if (!completer.isCompleted) completer.complete();
        });
        await Future.any([
          completer.future,
          Future.delayed(const Duration(milliseconds: 2000)),
        ]);
        _doneSub?.cancel();

      } else if (cmd.startsWith('right:') || cmd.startsWith('left:')) {
        final dist = double.tryParse(RegExp(r'\d+').firstMatch(cmd)?.group(0) ?? '10') ?? 10.0;
        final completer = Completer<void>();
        _doneSub = _mqtt.doneStream.listen((_) {
          if (!completer.isCompleted) completer.complete();
        });
        await completer.future.timeout(
          Duration(seconds: (dist / 5).round() + 3),
          onTimeout: () {},
        );
        _doneSub?.cancel();

      } else if (cmd == 'left' || cmd == 'right') {
        await Future.delayed(const Duration(milliseconds: 700));
      } else {
        await Future.delayed(const Duration(milliseconds: 600));
      }

      // Update command display
      setState(() {
        final idx = _pendingAiCommands.indexOf(cmd);
        if (idx < _pendingAiCommands.length - 1) {
          _currentlyExecuting = _pendingAiCommands[idx + 1];
        }
      });
    }

    final navProvider = NavigationProvider.instance;
    navProvider.updatePosition(curRow, curCol, curDir);

    if (mounted) {
      setState(() => _currentlyExecuting = null);
      _addSystemMessage("✓ Command sequence complete!");
    }
  }

  void _movePosition(int dir, int cells, int curRow, int curCol, void Function(int, int) update) {
    int newRow = curRow;
    int newCol = curCol;
    switch (dir) {
      case 0:
        newRow = curRow - cells;
        break;
      case 1:
        newCol = curCol + cells;
        break;
      case 2:
        newRow = curRow + cells;
        break;
      case 3:
        newCol = curCol - cells;
        break;
    }
    update(newRow, newCol);
  }

  @override
  void dispose() {
    _doneSub?.cancel();
    _connSub?.cancel();
    _textController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: RoverTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Row(
          children: [
            Icon(Icons.smart_toy_rounded, color: RoverTheme.primary),
            const SizedBox(width: 12),
            Text(
              'AI Assistant',
              style: theme.textTheme.titleLarge?.copyWith(fontSize: 20),
            ),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _isConnected ? Colors.green.withValues(alpha: 0.15) : Colors.red.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _isConnected ? Colors.green.withValues(alpha: 0.4) : Colors.red.withValues(alpha: 0.4)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isConnected ? Colors.green : Colors.red,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  _isConnected ? 'ONLINE' : 'OFFLINE',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: _isConnected ? Colors.green : Colors.red,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                return _buildMessageBubble(msg);
              },
            ),
          ),
          if (_pendingAiCommands.isNotEmpty && _currentlyExecuting != null)
            _buildExecutingBar(),
          _buildInputArea(),
        ],
      ),
      bottomNavigationBar: Container(
        height: 80,
        decoration: BoxDecoration(
          color: RoverTheme.background.withValues(alpha: 0.95),
          border: const Border(top: BorderSide(color: RoverTheme.outlineVariant, width: 0.5)),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildNavItem(context, Icons.sensors, 'STATUS', route: '/status'),
            _buildNavItem(context, Icons.videogame_asset, 'CONTROL', route: '/control'),
            _buildNavItem(context, Icons.map_rounded, 'MAPS', route: '/maps'),
            _buildNavItem(context, Icons.auto_awesome, 'AI', route: '/ai', active: true),
            _buildNavItem(context, Icons.settings, 'SETTINGS', route: '/settings'),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem(BuildContext context, IconData icon, String label,
      {required String route, bool active = false}) {
    return InkWell(
      onTap: active ? null : () => Navigator.pushReplacementNamed(context, route),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: active ? RoverTheme.primary.withValues(alpha: 0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: active ? RoverTheme.primary : RoverTheme.secondary, size: 22),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
                color: active ? RoverTheme.primary : RoverTheme.secondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage msg) {
    final isUser = msg.isUser;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: EdgeInsets.all(isUser ? 14 : 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        decoration: BoxDecoration(
          color: isUser
              ? RoverTheme.primary
              : (msg.isThinking
                  ? RoverTheme.surfaceContainerHigh
                  : RoverTheme.surfaceContainerLow),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isUser ? 18 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 18),
          ),
        ),
        child: msg.isThinking
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: RoverTheme.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    msg.text,
                    style: const TextStyle(
                      color: RoverTheme.secondary,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              )
            : Text(
                msg.text,
                style: TextStyle(
                  color: isUser ? Colors.white : null,
                  fontSize: 14,
                ),
              ),
      ),
    );
  }

  Widget _buildExecutingBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: RoverTheme.surfaceContainerHigh,
      child: Row(
        children: [
          const Icon(Icons.play_arrow_rounded, color: RoverTheme.primary, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Executing: $_currentlyExecuting',
              style: const TextStyle(
                color: RoverTheme.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Text(
            '${_pendingAiCommands.indexOf(_currentlyExecuting!) + 1}/${_pendingAiCommands.length}',
            style: const TextStyle(
              color: RoverTheme.secondary,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: RoverTheme.surfaceContainerLow,
        border: Border(
          top: BorderSide(color: RoverTheme.outlineVariant.withValues(alpha: 0.3)),
        ),
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _textController,
                focusNode: _focusNode,
                decoration: InputDecoration(
                  hintText: 'Type a command...',
                  hintStyle: const TextStyle(color: RoverTheme.secondary),
                  filled: true,
                  fillColor: RoverTheme.surfaceContainer,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                ),
                textInputAction: TextInputAction.send,
                onSubmitted: _handleSubmit,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _isVoiceActive ? Colors.red : RoverTheme.primary,
              ),
              child: IconButton(
                icon: Icon(
                  _isListening ? Icons.close_rounded : Icons.mic_rounded,
                  color: Colors.white,
                ),
                onPressed: _handleVoiceMicTap,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: RoverTheme.primary,
              ),
              child: IconButton(
                icon: const Icon(Icons.send_rounded, color: Colors.white),
                onPressed: () => _handleSubmit(_textController.text),
              ),
            ),
          ],
        ),
      ),
    );
  }
}