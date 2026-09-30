import 'dart:async';
import 'package:flutter/services.dart';

class NativeService {
  static final NativeService instance = NativeService._init();
  static const MethodChannel _channel = MethodChannel('com.cybolite.msgserver/channel');

  final StreamController<Map<String, dynamic>> _eventStreamController =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get onEventCaptured => _eventStreamController.stream;

  NativeService._init() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onEventCaptured') {
        final raw = call.arguments;
        if (raw is Map) {
          final event = Map<String, dynamic>.from(raw);
          _eventStreamController.add(event);
        }
      }
    });
  }


  Future<String> getDeviceId() async {
    try {
      final String? id = await _channel.invokeMethod('getDeviceId');
      return id ?? 'unknown-device';
    } catch (e) {
      return 'unknown-device';
    }
  }

  Future<List<Map<String, dynamic>>> getSimInfo() async {
    try {
      final result = await _channel.invokeListMethod('getSimInfo');
      if (result == null) return [];
      return result.map((item) => Map<String, dynamic>.from(item as Map)).toList();
    } catch (e) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getInstalledWhatsAppPackages() async {
    try {
      final result = await _channel.invokeListMethod('getInstalledWhatsAppPackages');
      if (result == null) return [];
      return result.map((item) => Map<String, dynamic>.from(item as Map)).toList();
    } catch (e) {
      return [];
    }
  }

  Future<bool> isNotificationListenerPermissionGranted() async {
    try {
      final bool? granted = await _channel.invokeMethod('isNotificationListenerPermissionGranted');
      return granted ?? false;
    } catch (e) {
      return false;
    }
  }

  Future<void> rebindNotificationListener() async {
    try {
      await _channel.invokeMethod('rebindNotificationListener');
    } catch (_) {}
  }

  Future<void> openNotificationListenerSettings() async {
    try {
      await _channel.invokeMethod('openNotificationListenerSettings');
    } catch (_) {}
  }

  Future<bool> isBatteryOptimizationIgnored() async {
    try {
      final bool? ignored = await _channel.invokeMethod('isBatteryOptimizationIgnored');
      return ignored ?? false;
    } catch (e) {
      return false;
    }
  }

  Future<void> requestIgnoreBatteryOptimizations() async {
    try {
      await _channel.invokeMethod('requestIgnoreBatteryOptimizations');
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> pollPendingEvents() async {
    try {
      final result = await _channel.invokeListMethod('pollPendingEvents');
      if (result == null) return [];
      return result.map((item) => Map<String, dynamic>.from(item as Map)).toList();
    } catch (e) {
      return [];
    }
  }
}
