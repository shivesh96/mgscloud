import 'dart:convert';
import 'dart:io' as io;

import 'package:dio/dio.dart';

import '../data/local/dao/event_dao.dart';
import '../data/local/dao/settings_dao.dart';
import '../domain/models/event_model.dart';
import 'auth_service.dart';
import 'native_service.dart';
import 'persistent_websocket_manager.dart';

class TransportManager {
  static final TransportManager instance = TransportManager._init();
  final EventDao _eventDao = EventDao();
  final SettingsDao _settingsDao = SettingsDao();
  final PersistentWebSocketManager _wsManager =
      PersistentWebSocketManager.instance;
  final Dio _dio = Dio();

  TransportManager._init();

  Future<Map<String, dynamic>> testConnection({
    required String serverUrl,
    required String protocol,
    required String method,
    required String authType,
    required String authToken,
  }) async {
    if (serverUrl.trim().isEmpty) {
      return {'success': false, 'message': 'Server URL cannot be empty'};
    }

    try {
      if (protocol == 'WebSocket') {
        var wsUrl = serverUrl.trim();
        if (wsUrl.startsWith('http://')) {
          wsUrl = wsUrl.replaceFirst('http://', 'ws://');
        }
        if (wsUrl.startsWith('https://')) {
          wsUrl = wsUrl.replaceFirst('https://', 'wss://');
        }
        if (!wsUrl.startsWith('ws://') && !wsUrl.startsWith('wss://')) {
          wsUrl = 'ws://$wsUrl';
        }

        io.WebSocket? tempWs;
        try {
          tempWs = await io.WebSocket.connect(wsUrl)
              .timeout(const Duration(seconds: 6));
          tempWs.add('ping');
          await Future.delayed(const Duration(milliseconds: 300));
          return {
            'success': true,
            'message': 'WebSocket reachable and verified! (Tested & closed, connection remains disconnected)',
          };
        } catch (e) {
          return {
            'success': false,
            'message': 'WebSocket connection failed: $e',
          };
        } finally {
          try {
            await tempWs?.close();
          } catch (_) {}
        }
      } else {
        // HTTP Test - Hits health check or ping endpoint
        var targetUrl = serverUrl.trim();
        if (targetUrl.startsWith('ws://')) {
          targetUrl = targetUrl.replaceFirst('ws://', 'http://');
        }
        if (targetUrl.startsWith('wss://')) {
          targetUrl = targetUrl.replaceFirst('wss://', 'https://');
        }
        if (!targetUrl.startsWith('http://') &&
            !targetUrl.startsWith('https://')) {
          targetUrl = 'http://$targetUrl';
        }

        final baseUri = Uri.parse(targetUrl);
        final host = baseUri.host;
        final port = baseUri.hasPort
            ? baseUri.port
            : (baseUri.scheme == 'https' ? 443 : 80);
        final healthUrl = '${baseUri.scheme}://$host:$port/api/v1/health';

        final options = Options(
          method: 'GET',
          sendTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 8),
          headers: {
            'Accept': 'application/json',
            if (authType == 'BEARER' && authToken.isNotEmpty)
              'Authorization': 'Bearer $authToken',
            if (authType == 'API_KEY' && authToken.isNotEmpty)
              'X-Api-Key': authToken,
            if (authType == 'BASIC' && authToken.isNotEmpty)
              'Authorization': 'Basic ${base64Encode(utf8.encode(authToken))}',
          },
          validateStatus: (status) => status != null && status < 500,
        );

        final response = await _dio.get(healthUrl, options: options);

        if (response.statusCode != null &&
            response.statusCode! >= 200 &&
            response.statusCode! < 300) {
          return {
            'success': true,
            'message': 'HTTP connection test successful! Server is online (Status: disconnected)',
          };
        } else if (response.statusCode == 401) {
          return {
            'success': false,
            'message': 'Authentication failed (401). If using Basic Auth, select BASIC and enter username:password.',
          };
        } else {
          return {
            'success': false,
            'message': 'Server returned status: ${response.statusCode}',
          };
        }
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Connection failed: ${e.toString().replaceAll('\n', ' ')}',
      };
    }
  }

  Future<bool> sendEvent(EventModel event) async {
    final settings = await _settingsDao.getSettings();
    final serverUrl = settings['server_url'] as String? ?? '';
    final protocol = settings['protocol'] as String? ?? 'WebSocket';
    final method = settings['http_method'] as String? ?? 'POST';
    final authType = settings['auth_type'] as String? ?? 'NONE';
    final authToken = settings['auth_token'] as String? ?? '';
    final timeoutSec = settings['connection_timeout'] as int? ?? 30;

    final isAuth = await AuthService.instance.isAuthenticated();

    if (serverUrl.trim().isEmpty && !isAuth) {
      if (event.id != null) {
        await _eventDao.updateEventStatus(
          event.id!,
          'failed',
          response: 'Server URL not configured',
          retryCount: event.retryCount + 1,
        );
      }
      return false;
    }

    final realDeviceId =
        (event.deviceId.isNotEmpty &&
            event.deviceId != 'android-device' &&
            event.deviceId != 'unknown')
        ? event.deviceId
        : await NativeService.instance.getDeviceId();

    final user = await AuthService.instance.getCurrentUser();
    final effectiveEvent = event.copyWith(
      deviceId: realDeviceId,
      userId: event.userId ?? user.effectiveUserId,
    );

    // 1. If WebSocket is selected or available, try WebSocket first with Server ACK
    if (protocol == 'WebSocket' || _wsManager.isConnected) {
      if (!_wsManager.isConnected) {
        await _wsManager.connect();
      }

      if (_wsManager.isConnected) {
        final ackReceived = await _wsManager.sendEventWithAck(effectiveEvent);
        if (ackReceived) {
          return true; // Sent successfully and ACK received
        }
      }
    }

    // 2. HTTP Fallback / Direct HTTP
    return await _sendViaHttp(
      serverUrl: serverUrl,
      method: method,
      authType: authType,
      authToken: authToken,
      timeoutSec: timeoutSec,
      payload: effectiveEvent.toServerPayload(),
      event: effectiveEvent,
    );
  }

  Future<bool> _sendViaHttp({
    required String serverUrl,
    required String method,
    required String authType,
    required String authToken,
    required int timeoutSec,
    required Map<String, dynamic> payload,
    required EventModel event,
  }) async {
    var httpUrl = serverUrl;
    if (httpUrl.startsWith('ws://')) {
      httpUrl = httpUrl.replaceFirst('ws://', 'http://');
    }
    if (httpUrl.startsWith('wss://')) {
      httpUrl = httpUrl.replaceFirst('wss://', 'https://');
    }
    if (!httpUrl.endsWith('/api/v1/events') && !httpUrl.contains('/events')) {
      final base = httpUrl.endsWith('/')
          ? httpUrl.substring(0, httpUrl.length - 1)
          : httpUrl;
      httpUrl = '$base/api/v1/events';
    }

    final user = await AuthService.instance.getCurrentUser();
    final effectiveToken = authToken.isNotEmpty ? authToken : user.authToken;
    final effectiveAuthType = authToken.isNotEmpty
        ? authType
        : (user.authToken.isNotEmpty ? 'BEARER' : 'NONE');

    final options = Options(
      method: method,
      sendTimeout: Duration(seconds: timeoutSec),
      receiveTimeout: Duration(seconds: timeoutSec),
      headers: {
        'Content-Type': 'application/json',
        'X-Device-Id': event.deviceId,
        if (effectiveAuthType == 'BEARER' && effectiveToken.isNotEmpty)
          'Authorization': 'Bearer $effectiveToken',
        if (effectiveAuthType == 'API_KEY' && effectiveToken.isNotEmpty)
          'X-Api-Key': effectiveToken,
        if (effectiveAuthType == 'BASIC' && effectiveToken.isNotEmpty)
          'Authorization': 'Basic ${base64Encode(utf8.encode(effectiveToken))}',
      },
      validateStatus: (status) => status != null && status < 500,
    );

    try {
      final response = method == 'POST'
          ? await _dio.post(httpUrl, data: payload, options: options)
          : await _dio.get(httpUrl, queryParameters: payload, options: options);

      if (response.statusCode != null &&
          response.statusCode! >= 200 &&
          response.statusCode! < 300) {
        if (event.id != null) {
          await _eventDao.updateEventStatus(
            event.id!,
            'sent',
            response: response.data?.toString() ?? 'HTTP 200 Accepted',
          );
        }
        return true;
      } else if (response.statusCode == 403) {
        final errData = response.data is Map ? response.data : {};
        final msg =
            errData['message'] ??
            'Device or Account is blocked (403 Forbidden)';
        if (event.id != null) {
          await _eventDao.updateEventStatus(
            event.id!,
            'blocked',
            response: 'Rejected by server: $msg',
          );
        }
        return false;
      } else {
        if (event.id != null) {
          await _eventDao.updateEventStatus(
            event.id!,
            'pending',
            response: 'HTTP ${response.statusCode}: ${response.data}',
            retryCount: event.retryCount + 1,
          );
        }
        return false;
      }
    } catch (e) {
      if (event.id != null) {
        await _eventDao.updateEventStatus(
          event.id!,
          'pending',
          response: 'Network error: $e',
          retryCount: event.retryCount + 1,
        );
      }
      return false;
    }
  }

  Future<int> syncPendingEvents() async {
    final pending = await _eventDao.getPendingEvents(limit: 50);
    int successCount = 0;
    for (final event in pending) {
      final ok = await sendEvent(event);
      if (ok) successCount++;
    }
    return successCount;
  }
}
