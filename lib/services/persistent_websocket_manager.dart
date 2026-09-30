import 'otp_parser_service.dart';
import 'native_service.dart';

import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../data/local/dao/event_dao.dart';
import '../data/local/dao/settings_dao.dart';
import '../domain/models/event_model.dart';
import 'auth_service.dart';

enum WsConnectionState { disconnected, connecting, connected, reconnecting }

class PersistentWebSocketManager {
  static final PersistentWebSocketManager instance =
      PersistentWebSocketManager._init();
  final SettingsDao _settingsDao = SettingsDao();
  final EventDao _eventDao = EventDao();
  final AuthService _authService = AuthService.instance;

  WebSocketChannel? _channel;
  WsConnectionState _state = WsConnectionState.disconnected;

  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  bool _isDisposed = false;

  final StreamController<WsConnectionState> _stateController =
      StreamController<WsConnectionState>.broadcast();
  Stream<WsConnectionState> get stateStream => _stateController.stream;
  WsConnectionState get currentState => _state;
  bool get isConnected => _state == WsConnectionState.connected;

  // Pending ACKs: event_id -> Completer<bool>
  final Map<String, Completer<bool>> _pendingAcks = {};

  PersistentWebSocketManager._init();

  void _setState(WsConnectionState newState) {
    if (_state != newState) {
      _state = newState;
      _stateController.add(_state);
    }
  }

  Future<void> connect({bool force = false}) async {
    if (_isDisposed) return;
    if (!await _authService.isAuthenticated()) {
      disconnect();
      return;
    }
    if (!force &&
        (_state == WsConnectionState.connected ||
            _state == WsConnectionState.connecting)) {
      return;
    }

    final settings = await _settingsDao.getSettings();
    var serverUrl = settings['server_url'] as String? ?? '';

    if (serverUrl.isEmpty) {
      _setState(WsConnectionState.disconnected);
      return;
    }

    // Convert HTTP to WS if needed
    if (serverUrl.startsWith('http://')) {
      serverUrl = serverUrl.replaceFirst('http://', 'ws://');
    } else if (serverUrl.startsWith('https://')) {
      serverUrl = serverUrl.replaceFirst('https://', 'wss://');
    }
    if (!serverUrl.startsWith('ws://') && !serverUrl.startsWith('wss://')) {
      serverUrl = 'ws://$serverUrl';
    }
    _setState(
      _reconnectAttempts > 0
          ? WsConnectionState.reconnecting
          : WsConnectionState.connecting,
    );

    try {
      final uri = Uri.parse(serverUrl);
      _channel = WebSocketChannel.connect(uri);

      await _channel!.ready.timeout(const Duration(seconds: 10));

      _setState(WsConnectionState.connected);
      _reconnectAttempts = 0;
      _reconnectTimer?.cancel();

      // Send AUTH handshake
      final user = await _authService.getCurrentUser();
      _channel!.sink.add(
        jsonEncode({
          'type': 'AUTH',
          'token': user.authToken,
          'user_id': user.effectiveUserId,
          'device_id': await NativeService.instance.getDeviceId(),
        }),
      );

      // Start ping heartbeat
      _startHeartbeat();

      // Listen for incoming messages and ACKs
      _channel!.stream.listen(
        (data) => _handleIncomingMessage(data),
        onError: (err) => _handleDisconnect('Error: $err'),
        onDone: () => _handleDisconnect('Connection closed by server'),
        cancelOnError: true,
      );

      // Immediately flush any offline pending events
      _flushPendingQueue();
    } catch (e) {
      _handleDisconnect('Connect failure: $e');
    }
  }

  void _handleIncomingMessage(dynamic data) {
    try {
      final rawStr = data.toString();
      if (rawStr.toLowerCase() == 'pong') {
        return; // Heartbeat healthy
      }

      final msg = jsonDecode(rawStr);
      if (msg is Map) {
        final type = msg['type'] as String?;
        final eventId = msg['event_id'] as String?;

        if (type == 'ACK' && eventId != null) {
          final completer = _pendingAcks.remove(eventId);
          if (completer != null && !completer.isCompleted) {
            completer.complete(true);
          }
          _markEventSent(eventId, msg['status']?.toString() ?? 'ACK received');
        } else if (type == 'config_sync' || type == 'ROLE_CHANGED') {
          OtpParserService.instance.syncRulesFromServer();
        } else if (type == 'PERMISSION_UPDATED') {
          _authService.validateAndRefreshUser();
        } else if (type == 'USER_BLOCKED') {
          _authService.handleServerPermissionUpdate(status: 'blocked');
        } else if (type == 'SESSION_TERMINATED') {
          _authService.logout();
        } else if (type == 'FORWARDING_MODE_CHANGED') {
          final mode = msg['mode'] as String?;
          if (mode != null) {
            _settingsDao.setSendFilteredOnly(mode == 'filtered');
          }
        }
      }
    } catch (_) {
      // Ignored non-JSON text
    }
  }

  Future<void> _markEventSent(String eventId, String response) async {
    final ev = await _eventDao.getEventByUuid(eventId);
    if (ev != null && ev.id != null) {
      await _eventDao.updateEventStatus(ev.id!, 'sent', response: response);
    }
  }

  void _handleDisconnect(String reason) {
    _setState(WsConnectionState.disconnected);
    _heartbeatTimer?.cancel();
    _channel = null;

    // Fail all waiting ACKs
    for (final completer in _pendingAcks.values) {
      if (!completer.isCompleted) completer.complete(false);
    }
    _pendingAcks.clear();

    _scheduleReconnect();
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 25), (timer) {
      if (_state == WsConnectionState.connected && _channel != null) {
        try {
          _channel!.sink.add('ping');
        } catch (_) {
          _handleDisconnect('Heartbeat write failed');
        }
      }
    });
  }

  void _scheduleReconnect() {
    if (_isDisposed) return;
    _reconnectTimer?.cancel();

    // Exponential backoff: 2s, 4s, 8s, up to max 30s
    _reconnectAttempts++;
    final delaySec = (_reconnectAttempts * 2).clamp(2, 30);

    _setState(WsConnectionState.reconnecting);
    _reconnectTimer = Timer(Duration(seconds: delaySec), () {
      connect();
    });
  }

  Future<bool> sendEventWithAck(
    EventModel event, {
    Duration timeout = const Duration(seconds: 8),
  }) async {
    if (_state != WsConnectionState.connected || _channel == null) {
      return false;
    }

    final completer = Completer<bool>();
    _pendingAcks[event.eventId] = completer;

    try {
      final payload = event.toServerPayload();
      _channel!.sink.add(
        jsonEncode({
          'type': 'EVENT',
          'event_id': event.eventId,
          'payload': payload,
        }),
      );

      // Await server ACK with timeout
      final success = await completer.future.timeout(
        timeout,
        onTimeout: () {
          _pendingAcks.remove(event.eventId);
          return false;
        },
      );

      if (success) {
        if (event.id != null) {
          await _eventDao.updateEventStatus(
            event.id!,
            'sent',
            response: 'Server ACK confirmed',
          );
        }
        return true;
      }
      return false;
    } catch (e) {
      _pendingAcks.remove(event.eventId);
      return false;
    }
  }

  Future<void> _flushPendingQueue() async {
    try {
      final pending = await _eventDao.getPendingEvents(limit: 50);
      for (final ev in pending) {
        if (!isConnected) break;
        await sendEventWithAck(ev);
      }
    } catch (_) {}
  }

  void disconnect() {
    _reconnectTimer?.cancel();
    _heartbeatTimer?.cancel();
    _channel?.sink.close();
    _channel = null;
    _setState(WsConnectionState.disconnected);
  }

  void dispose() {
    _isDisposed = true;
    disconnect();
    _stateController.close();
  }
}
