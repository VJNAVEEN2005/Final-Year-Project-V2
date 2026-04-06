import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/rover_theme.dart';
import '../services/mqtt_service.dart';
import '../services/ai_service.dart';
import '../services/voice_service.dart';

class AiAssistantScreen extends StatefulWidget {
  const AiAssistantScreen({super.key});

  @override
  State<AiAssistantScreen> createState() => _AiAssistantScreenState();
}

class _AiAssistantScreenState extends State<AiAssistantScreen>
    with TickerProviderStateMixin {
  final MqttService _mqtt = MqttService.instance;

  bool _isVoiceActive = false;
  bool _isListening = false;
  bool _isAiThinking = false;
  String _voiceResultText = "Tap the mic to start command...";
  List<String> _pendingAiCommands = [];
  String? _currentlyExecuting;
  StreamSubscription? _doneSub;

  Future<void> _handleVoiceMicTap() async {
    if (_isVoiceActive) {
      if (_isListening) {
        VoiceService.instance.stopListening();
        setState(() => _isListening = false);
      } else {
        setState(() => _isVoiceActive = false);
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
      _voiceResultText = "Listening for command...";
      _pendingAiCommands = [];
    });

    VoiceService.instance.startListening((text) {
      if (mounted) {
        setState(() {
          _voiceResultText = text;
          _isListening = false;
          _isAiThinking = true;
        });
        _processAiInput(text);
      }
    });
  }

  Future<void> _processAiInput(String voiceText) async {
    if (voiceText.isEmpty) {
      setState(() => _isVoiceActive = false);
      return;
    }

    final commands = await AiService.instance.getCommands(voiceText);
    if (!mounted) return;

    if (commands.isEmpty) {
      setState(() {
        _isAiThinking = false;
        _voiceResultText = "I didn't understand that command.";
      });
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _isVoiceActive = false);
      });
      return;
    }

    setState(() {
      _isAiThinking = false;
      _pendingAiCommands = commands;
    });

    final confirmText = "Executing sequence: ${commands.join(', ')}";
    VoiceService.instance.speak(confirmText);

    _executeAisSequence(commands);
  }

  Future<void> _executeAisSequence(List<String> commands) async {
    for (final cmd in commands) {
      if (!mounted) break;
      setState(() => _currentlyExecuting = cmd);
      
      _mqtt.publish(cmd);

      if (cmd.startsWith('move:')) {
        final completer = Completer<void>();
        _doneSub = _mqtt.doneStream.listen((_) {
          if (!completer.isCompleted) completer.complete();
        });
        
        final dist = double.tryParse(cmd.substring(5)) ?? 10;
        await completer.future.timeout(
          Duration(seconds: (dist / 5).round() + 3),
          onTimeout: () => debugPrint('[AI] Move timeout, forcing next'),
        );
        _doneSub?.cancel();
      } else {
        await Future.delayed(const Duration(milliseconds: 600));
      }
    }

    if (mounted) {
      setState(() {
        _currentlyExecuting = "Complete!";
      });
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _isVoiceActive = false);
      });
    }
  }

  @override
  void dispose() {
    _doneSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.black.withOpacity(0.85),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Row(
          children: [
            const Icon(Icons.auto_awesome, color: RoverTheme.primary),
            const SizedBox(width: 12),
            Text(
              'AI Assistant',
              style: theme.textTheme.titleLarge?.copyWith(fontSize: 20, color: Colors.white),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomNav(context),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: _buildVoiceFab(),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 60),
            if (_isListening || _isAiThinking)
              _buildPulsar()
            else
              const SizedBox(height: 120), // Placeholder for pulsar
            
            const SizedBox(height: 40),
            
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                _voiceResultText,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w300,
                  fontStyle: _isListening ? FontStyle.italic : null,
                ),
              ),
            ),

            if (_isAiThinking)
              const Padding(
                padding: EdgeInsets.only(top: 20),
                child: Text('AI is thinking...', 
                  style: TextStyle(color: RoverTheme.secondary, fontSize: 12)),
              ),

            if (_pendingAiCommands.isNotEmpty)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: Column(
                    children: [
                      const Text('COMMAND SEQUENCE', 
                        style: TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 2)),
                      const SizedBox(height: 16),
                      for (final c in _pendingAiCommands)
                        _buildCmdRow(c),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildVoiceFab() {
    return Container(
      height: 72,
      width: 72,
      margin: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: _handleVoiceMicTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _isVoiceActive ? Colors.red : RoverTheme.primary,
            boxShadow: [
              BoxShadow(
                color: (_isVoiceActive ? Colors.red : RoverTheme.primary)
                    .withOpacity(0.4),
                blurRadius: _isListening ? 25 : 12,
                spreadRadius: _isListening ? 6 : 0,
              ),
            ],
          ),
          child: Icon(
            _isVoiceActive 
              ? (_isListening ? Icons.hearing_rounded : Icons.close_rounded)
              : Icons.mic_rounded,
            color: Colors.white,
            size: 32,
          ),
        ),
      ),
    );
  }

  Widget _buildPulsar() {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.8, end: 1.2),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeInOut,
      builder: (context, value, child) {
        return Container(
          width: 120 * value,
          height: 120 * value,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: RoverTheme.primary.withOpacity(0.5 / value), width: 2),
            boxShadow: [
              BoxShadow(
                color: RoverTheme.primary.withOpacity(0.2 / value),
                blurRadius: 40,
                spreadRadius: 20,
              )
            ],
          ),
          child: const Center(
            child: Icon(Icons.auto_awesome, color: RoverTheme.primary, size: 40),
          ),
        );
      },
    );
  }

  Widget _buildCmdRow(String cmd) {
    final isDone = _pendingAiCommands.indexOf(cmd) < 
                  (_pendingAiCommands.indexOf(_currentlyExecuting ?? '') == -1 
                      ? 0 : _pendingAiCommands.indexOf(_currentlyExecuting!));
    final isCurrent = _currentlyExecuting == cmd;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isDone ? Icons.check_circle_rounded : (isCurrent ? Icons.play_circle_filled_rounded : Icons.circle_outlined),
            size: 16,
            color: isCurrent ? RoverTheme.primary : (isDone ? Colors.green : Colors.white24),
          ),
          const SizedBox(width: 12),
          Text(
            cmd.toUpperCase(),
            style: TextStyle(
              color: isCurrent ? Colors.white : Colors.white38,
              fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNav(BuildContext context) {
    return Container(
      height: 80,
      decoration: BoxDecoration(
        color: RoverTheme.background.withOpacity(0.95),
        border: const Border(
            top: BorderSide(color: RoverTheme.outlineVariant, width: 0.5)),
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
          color: active ? RoverTheme.primary.withOpacity(0.1) : Colors.transparent,
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
}
