import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';


class MqttService {
  // ─── Singleton ────────────────────────────────────────────────────────────
  MqttService._internal();
  static final MqttService instance = MqttService._internal();

  static const String _host     = 'wss://kc7f274c.ala.us-east-1.emqxsl.com/mqtt';
  static const int    _port     = 8084;


  static const String _username = 'vjnaveen2005';
  static const String _password = 'Naveenvel@31';
  static const String topicCmd    = 'rover/cmd';
  static const String topicData   = 'rover/data';
  static const String topicStatus = 'rover/status';

  // ─── State ────────────────────────────────────────────────────────────────
  MqttServerClient? _client;
  bool _isConnected   = false;
  bool _isConnecting  = false;
  bool _isRoverOnline = false;

  final _dataCtrl  = StreamController<String>.broadcast();
  final _connCtrl  = StreamController<bool>.broadcast();
  final _roverCtrl = StreamController<bool>.broadcast();

  Stream<String> get dataStream        => _dataCtrl.stream;
  Stream<bool>   get connectionStream  => _connCtrl.stream;
  Stream<bool>   get roverStatusStream => _roverCtrl.stream;
  bool get isConnected   => _isConnected;
  bool get isRoverOnline => _isRoverOnline;

  // ─── Connect ──────────────────────────────────────────────────────────────
  Future<void> connect() async {
    if (_isConnecting || _isConnected) return;
    _isConnecting = true;

    try {
      final clientId = 'FlutterRover-${DateTime.now().millisecondsSinceEpoch}';
      _client = MqttServerClient.withPort(_host, clientId, _port);

      _client!.useWebSocket = true;
      _client!.websocketProtocols = MqttClientConstants.protocolsSingleDefault;
      _client!.onBadCertificate = (dynamic _) => true;
      _client!.keepAlivePeriod = 60;
      _client!.connectTimeoutPeriod = 20000;
      _client!.autoReconnect = true;
      _client!.logging(on: false);

      _client!.connectionMessage = MqttConnectMessage()
          .withClientIdentifier(clientId)
          .authenticateAs(_username, _password)
          .startClean();

      _client!.onConnected       = _onConnected;
      _client!.onDisconnected    = _onDisconnected;
      _client!.onAutoReconnected = _onAutoReconnected;

      debugPrint('[MQTT] ▶ Connecting WSS $_host:$_port clientId=$clientId');
      final status = await _client!.connect();
      debugPrint('[MQTT] ▶ State after connect: ${status?.state}');

    } catch (e, st) {
      debugPrint('[MQTT] ✗ connect() error: $e');
      debugPrint('[MQTT] ✗ stacktrace: $st');
      _isConnected  = false;
      _isConnecting = false;
      _connCtrl.add(false);
      try { _client?.disconnect(); } catch (_) {}
    }

    _isConnecting = false;
  }


  // ─── Callbacks ────────────────────────────────────────────────────────────

  void _onConnected() {
    _isConnected = true;
    _connCtrl.add(true);
    debugPrint('[MQTT] ✅ Connected');

    _client!.subscribe(topicData,   MqttQos.atMostOnce);
    _client!.subscribe(topicStatus, MqttQos.atMostOnce);

    _client!.updates!.listen((msgs) {
      for (final m in msgs) {
        final payload = MqttPublishPayload.bytesToStringAsString(
            (m.payload as MqttPublishMessage).payload.message);
        debugPrint('[MQTT] ← ${m.topic}: $payload');
        if (m.topic == topicData) {
          _dataCtrl.add(payload);
        } else if (m.topic == topicStatus) {
          _isRoverOnline = payload.trim() == 'online';
          _roverCtrl.add(_isRoverOnline);
        }
      }
    });
  }

  void _onDisconnected() {
    _isConnected   = false;
    _isRoverOnline = false;
    _connCtrl.add(false);
    _roverCtrl.add(false);
    debugPrint('[MQTT] ❌ Disconnected');
  }

  void _onAutoReconnected() {
    _isConnected = true;
    _connCtrl.add(true);
    _client?.subscribe(topicData,   MqttQos.atMostOnce);
    _client?.subscribe(topicStatus, MqttQos.atMostOnce);
    debugPrint('[MQTT] 🔄 Auto-reconnected');
  }

  // ─── Publish ──────────────────────────────────────────────────────────────
  void publish(String command) {
    if (!_isConnected || _client == null) return;
    final builder = MqttClientPayloadBuilder()..addString(command);
    _client!.publishMessage(topicCmd, MqttQos.atMostOnce, builder.payload!);
    debugPrint('[MQTT] → $topicCmd: $command');
  }

  // ─── Disconnect ───────────────────────────────────────────────────────────
  void disconnect() {
    publish('stop');
    _client?.disconnect();
    _isConnected = false;
  }
}
