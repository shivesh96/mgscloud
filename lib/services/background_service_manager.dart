import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';

import 'email_reader_service.dart';
import 'event_coordinator.dart';
import 'transport_manager.dart';
import 'auth_service.dart';
import '../data/local/dao/settings_dao.dart';

@pragma('vm:entry-point')
class BackgroundServiceManager {
  static final BackgroundServiceManager instance =
      BackgroundServiceManager._init();
  FlutterBackgroundService? _service;
  FlutterBackgroundService get _client =>
      _service ??= FlutterBackgroundService();

  BackgroundServiceManager._init();

  Future<void> initialize() async {
    try {
      await _client.configure(
        androidConfiguration: AndroidConfiguration(
          onStart: onBackgroundServiceStart,
          // The worker checks authentication on startup and stops itself for a
          // guest session, but a valid session resumes after reboot/lock.
          autoStart: true,
          isForegroundMode: true,
          notificationChannelId: 'msg_to_server_channel',
          initialNotificationTitle: 'Message Cloud',
          initialNotificationContent:
              'Monitoring SMS, WhatsApp & Emails in background',
          foregroundServiceNotificationId: 888,
          foregroundServiceTypes: [AndroidForegroundType.dataSync],
        ),
        iosConfiguration: IosConfiguration(
          autoStart: true,
          onForeground: onBackgroundServiceStart,
          onBackground: onBackgroundServiceIosBackground,
        ),
      );
    } catch (_) {}
  }

  Future<bool> isRunning() async {
    try {
      return await _client.isRunning();
    } catch (_) {
      return false;
    }
  }

  Future<void> startService() async {
    try {
      final settings = await SettingsDao().getSettings();
      final isEnabled = (settings['service_enabled'] as int? ?? 1) == 1;
      final serverUrl = settings['server_url'] as String? ?? '';
      final isAuth = await AuthService.instance.isAuthenticated();

      if (!isEnabled || (!isAuth && serverUrl.trim().isEmpty)) {
        await stopService();
        return;
      }
      final running = await _client.isRunning();
      if (!running) {
        await _client.startService();
      }
    } catch (_) {}
  }

  Future<void> stopService() async {
    try {
      _client.invoke('stopService');
    } catch (_) {}
  }
}

@pragma('vm:entry-point')
Future<bool> onBackgroundServiceIosBackground(ServiceInstance service) async {
  return true;
}

@pragma('vm:entry-point')
void onBackgroundServiceStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  WidgetsFlutterBinding.ensureInitialized();

  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  try {
    final settings = await SettingsDao().getSettings();
    final isEnabled = (settings['service_enabled'] as int? ?? 1) == 1;
    final serverUrl = settings['server_url'] as String? ?? '';
    final isAuth = await AuthService.instance.isAuthenticated();

    if (!isEnabled || (!isAuth && serverUrl.trim().isEmpty)) {
      service.stopSelf();
      return;
    }
    await EventCoordinator.instance.initialize();
    await EmailReaderService.instance.startAllListeners();
  } catch (_) {}

  // Run periodic tasks: sync pending offline events & drain native events
  Timer.periodic(const Duration(seconds: 15), (timer) async {
    try {
      await EventCoordinator.instance.drainBufferedNativeEvents();
      await TransportManager.instance.syncPendingEvents();
    } catch (_) {}
  });
}
