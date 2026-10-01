import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/local/dao/event_dao.dart';
import '../data/local/dao/settings_dao.dart';
import '../data/local/dao/sim_dao.dart';
import '../data/local/dao/whatsapp_dao.dart';
import '../domain/models/event_model.dart';
import '../domain/models/sim_info_model.dart';
import 'auth_service.dart';
import 'native_service.dart';
import 'otp_parser_service.dart';
import 'persistent_websocket_manager.dart';
import 'sim_service.dart';
import 'transport_manager.dart';

class EventCoordinator {
  static final EventCoordinator instance = EventCoordinator._init();
  final EventDao _eventDao = EventDao();
  final SettingsDao _settingsDao = SettingsDao();
  final SimDao _simDao = SimDao();
  final WhatsAppDao _whatsAppDao = WhatsAppDao();
  final NativeService _nativeService = NativeService.instance;
  final TransportManager _transportManager = TransportManager.instance;
  final PersistentWebSocketManager _wsManager =
      PersistentWebSocketManager.instance;
  final OtpParserService _otpParser = OtpParserService.instance;
  final AuthService _authService = AuthService.instance;
  final Uuid _uuid = const Uuid();

  final StreamController<EventModel> _processedEventStream =
      StreamController<EventModel>.broadcast();

  Stream<EventModel> get onEventProcessed => _processedEventStream.stream;

  bool _initialized = false;
  Timer? _pollingTimer;
  Timer? _ruleSyncTimer;
  String _deviceId = 'android-device';

  void stopPolling() {
    _ruleSyncTimer?.cancel();
    _ruleSyncTimer = null;
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }

  EventCoordinator._init();

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    _deviceId = await _nativeService.getDeviceId();

    // Server configuration is private: never fetch rules before an account
    // has authenticated. The periodic job becomes active after login.
    if (await _authService.isAuthenticated()) {
      _otpParser.syncBidirectional();
      _ruleSyncTimer = Timer.periodic(const Duration(minutes: 5), (_) {
        _otpParser.syncBidirectional();
      });
    }

    // Connect persistent WebSocket connection
    try {
      await _wsManager.connect();
    } catch (_) {}

    // Listen to real-time events from native Android Activity (when UI is active)
    _nativeService.onEventCaptured.listen((rawEvent) {
      processIncomingNativeEvent(rawEvent);
    });

    // Drain any events persisted while app was inactive or in background
    await drainBufferedNativeEvents();

    // Start a periodic polling timer to ensure real-device events are never missed in background
    _pollingTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      drainBufferedNativeEvents();
    });
  }

  Future<void> activateAuthenticatedSession() async {
    if (!await _authService.isAuthenticated()) return;
    if (_ruleSyncTimer != null) return;
    await _otpParser.syncBidirectional();
    _ruleSyncTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      _otpParser.syncBidirectional();
    });
    await _wsManager.connect();
  }

  Future<void> drainBufferedNativeEvents() async {
    // MainActivity owns this channel and is not available to the dedicated
    // background Flutter engine. A failure here must never prevent the worker
    // from draining the SharedPreferences queue written by SmsBroadcastReceiver.
    try {
      await _nativeService.rebindNotificationListener();
      final nativeEvents = await _nativeService.pollPendingEvents();
      for (final raw in nativeEvents) {
        await processIncomingNativeEvent(raw);
      }
    } catch (_) {}

    try {
      // Persisted native events are available while the UI is closed/locked.
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      for (final key in [
        'flutter.pending_events',
        'flutter_pending_events',
        'pending_events',
      ]) {
        final pendingJson = prefs.getString(key);
        if (pendingJson != null &&
            pendingJson.isNotEmpty &&
            pendingJson != '[]') {
          await prefs.remove(key);
          final List<dynamic> events = jsonDecode(pendingJson);
          for (final raw in events) {
            if (raw is Map) {
              await processIncomingNativeEvent(Map<String, dynamic>.from(raw));
            }
          }
        }
      }
    } catch (_) {}
  }

  Future<EventModel?> processIncomingNativeEvent(
    Map<String, dynamic> raw,
  ) async {
    try {
      final isTest = raw['is_test'] == true;
      final isEnabled = await _settingsDao.isServiceEnabled();
      if (!isEnabled && !isTest) return null;

      final eventId = raw['event_id'] as String? ?? _uuid.v4();

      // Deduplication check: ignore if already processed
      final existing = await _eventDao.getEventByUuid(eventId);
      if (existing != null) {
        return existing;
      }

      final source = raw['source'] as String? ?? 'system';
      final packageName = raw['package_name'] as String?;
      final isSmsApp =
          source == 'sms' ||
          (packageName != null &&
              (packageName == 'com.google.android.apps.messaging' ||
                  packageName == 'com.android.mms' ||
                  packageName == 'com.samsung.android.messaging' ||
                  packageName == 'com.xiaomi.xmsf' ||
                  packageName.contains('messaging') ||
                  packageName.contains('.mms')));
      final isWhatsApp =
          source == 'whatsapp' ||
          (packageName != null &&
              (packageName == 'com.whatsapp' ||
                  packageName == 'com.whatsapp.w4b' ||
                  packageName.contains('whatsapp') ||
                  packageName.contains('dual') ||
                  packageName.contains('parallel') ||
                  packageName.contains('clone')));

      final isEmailApp =
          source == 'email' ||
          (packageName != null &&
              (packageName == 'com.google.android.gm' ||
                  packageName == 'com.microsoft.office.outlook' ||
                  packageName == 'com.google.android.apps.inbox' ||
                  packageName.contains('email') ||
                  packageName.contains('.mail')));

      final effectiveSource = isSmsApp
          ? 'sms'
          : (isWhatsApp ? 'whatsapp' : (isEmailApp ? 'email' : source));

      final eventType = isSmsApp
          ? 'sms_received'
          : (isEmailApp
                ? 'email_received'
                : (raw['event_type'] as String? ??
                      (isWhatsApp ? 'notification_received' : 'event')));
      final rawSender = raw['sender'] as String?;
      final rawTitle = raw['title'] as String?;
      final rawMessage = raw['message'] as String? ?? '';
      final rawServiceCenter = raw['service_center'] as String?;
      final userProfileId = raw['user_profile_id'] as String?;

      // Determine clean, non-null sender (fallback to title if sender is empty or Unknown)
      final effectiveSender =
          (rawSender != null && rawSender.isNotEmpty && rawSender != 'Unknown')
          ? rawSender
          : (rawTitle != null && rawTitle.isNotEmpty ? rawTitle : 'Unknown');

      final simSlot = raw['sim_slot'] as int?;
      final subId = raw['subscription_id'] as int?;

      String? simName;
      String? simNumber;
      String? instanceName;
      String? userPhoneNumber;
      int? resolvedSlot = simSlot;

      // 1. Resolve SIM information for SMS events
      if (effectiveSource == 'sms') {
        resolvedSlot = simSlot ?? 0;
        var allSims = await _simDao.getAllSims();
        if (allSims.isEmpty) {
          try {
            allSims = await SimService().detectAndSyncSims();
          } catch (_) {}
        }

        SimInfoModel? matchedSim;

        if (allSims.length == 1) {
          // SINGLE SIM PHONE:
          // There is only ONE SIM card installed. Every incoming SMS physically
          // arrived on this SIM card, regardless of whether the OS broadcast
          // reported subId as 1, the carrier subscription ID (e.g. 4), or slot as 0 or 1.
          matchedSim = allSims.first;
        } else if (allSims.isNotEmpty) {
          // MULTI-SIM PHONE:
          // 1. Exact match by native subscriptionId
          if (subId != null && subId > 0) {
            matchedSim = allSims.cast<SimInfoModel?>().firstWhere(
              (s) => s?.subscriptionId == subId,
              orElse: () => null,
            );
          }

          // 2. Direct match by 0-based slotIndex
          if (matchedSim == null && simSlot != null && simSlot >= 0) {
            matchedSim = allSims.cast<SimInfoModel?>().firstWhere(
              (s) => s?.slotIndex == simSlot,
              orElse: () => null,
            );
          }

          // 3. Many OEM intents use 1-based subId (subId 1 -> slot 0, subId 2 -> slot 1)
          if (matchedSim == null && subId != null && subId > 0) {
            final zeroBasedSlot = subId - 1;
            matchedSim = allSims.cast<SimInfoModel?>().firstWhere(
              (s) => s?.slotIndex == zeroBasedSlot,
              orElse: () => null,
            );
          }

          // 4. Many OEM intents use 1-based slotIndex (slot 1 -> slot 0)
          if (matchedSim == null && simSlot != null && simSlot > 0) {
            final zeroBasedSlot = simSlot - 1;
            matchedSim = allSims.cast<SimInfoModel?>().firstWhere(
              (s) => s?.slotIndex == zeroBasedSlot,
              orElse: () => null,
            );
          }

          // 5. Fallback to first enabled SIM or first available SIM
          matchedSim ??= allSims.firstWhere((s) => s.enabled, orElse: () => allSims.first);
        }

        if (matchedSim != null) {
          simName = matchedSim.effectiveName;
          simNumber = (matchedSim.effectiveNumber.isNotEmpty &&
                  matchedSim.effectiveNumber != 'Not configured')
              ? matchedSim.effectiveNumber
              : (matchedSim.userPhoneNumber.isNotEmpty
                  ? matchedSim.userPhoneNumber
                  : (matchedSim.detectedNumber.isNotEmpty
                      ? matchedSim.detectedNumber
                      : null));
          resolvedSlot = matchedSim.slotIndex;
        } else {
          resolvedSlot = simSlot ?? 0;
          simName = 'SIM ${resolvedSlot + 1}';
        }
      }

      // 2. Resolve WhatsApp configuration for notification events
      if (effectiveSource == 'whatsapp') {
        if (packageName != null) {
          final waConfig = await _whatsAppDao.findConfigByPackage(packageName);
          if (waConfig != null) {
            if (!waConfig.enabled && !isTest) {
              return null; // Ignored if instance disabled
            }
            instanceName = waConfig.instanceName.isNotEmpty
                ? waConfig.instanceName
                : 'WhatsApp';
            userPhoneNumber = waConfig.phoneNumber;
          } else {
            final allWa = await _whatsAppDao.getAllInstances();
            if (allWa.isNotEmpty) {
              instanceName = allWa.first.instanceName.isNotEmpty
                  ? allWa.first.instanceName
                  : 'WhatsApp';
              userPhoneNumber = allWa.first.phoneNumber;
            } else {
              instanceName = packageName == 'com.whatsapp.w4b'
                  ? 'WhatsApp Business'
                  : 'WhatsApp';
            }
          }
        } else {
          final allWa = await _whatsAppDao.getAllInstances();
          if (allWa.isNotEmpty) {
            instanceName = allWa.first.instanceName.isNotEmpty
                ? allWa.first.instanceName
                : 'WhatsApp';
            userPhoneNumber = allWa.first.phoneNumber;
          }
        }
      }

      // 3. OTP Parsing via Configurable Rules
      final extractedOtp = await _otpParser.parseOtp(
        body: rawMessage,
        sender: effectiveSender,
        serviceCenter: rawServiceCenter,
        type: effectiveSource,
      );

      // 4. Match receiving number to bound user
      String? receivingNumber;
      if (simNumber != null &&
          simNumber.isNotEmpty &&
          simNumber != 'Not configured') {
        receivingNumber = simNumber;
      } else if (userPhoneNumber != null &&
          userPhoneNumber.isNotEmpty &&
          userPhoneNumber != 'Not configured') {
        receivingNumber = userPhoneNumber;
      } else {
        final allSims = await _simDao.getAllSims();
        final firstSimNum =
            allSims.isNotEmpty ? allSims.first.effectiveNumber : null;
        if (firstSimNum != null &&
            firstSimNum.isNotEmpty &&
            firstSimNum != 'Not configured') {
          receivingNumber = firstSimNum;
        } else {
          final currentUser = await _authService.getCurrentUser();
          if (currentUser.mobile.isNotEmpty) {
            receivingNumber = currentUser.mobile;
          }
        }
      }

      final boundUserId = receivingNumber != null
          ? await _authService.findBoundUserIdFor(receivingNumber)
          : null;

      final ts =
          raw['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch;
      final isoDate = DateTime.fromMillisecondsSinceEpoch(ts).toIso8601String();

      bool contentHidden = raw['content_hidden'] == true;

      String deliveryStatus = 'pending';
      final isFilteredOnly = await _settingsDao.isSendFilteredOnly();
      if (isFilteredOnly && extractedOtp == null && !isTest) {
        deliveryStatus = 'filtered_out';
      }

      final event = EventModel(
        eventId: eventId,
        deviceId: _deviceId,
        eventType: eventType,
        source: effectiveSource,
        timestamp: isoDate,
        simSlot: effectiveSource == 'sms' ? resolvedSlot : simSlot,
        simName: simName,
        simNumber: simNumber,
        sender: effectiveSender,
        title: rawTitle ?? effectiveSender,
        message: rawMessage,
        packageName: packageName,
        instanceName: instanceName,
        userPhoneNumber: userPhoneNumber,
        userProfileId: userProfileId,
        serviceCenter: rawServiceCenter,
        otp: extractedOtp,
        userId: boundUserId,
        targetMobile: receivingNumber,
        deliveryStatus: deliveryStatus,
        contentHidden: contentHidden,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );

      final id = await _eventDao.insertEvent(event);
      final saved = event.copyWith(id: id);

      _processedEventStream.add(saved);

      if (deliveryStatus != 'filtered_out') {
        _transportManager.sendEvent(saved).then((ok) {
          if (ok) {
            final updated = saved.copyWith(deliveryStatus: 'sent');
            _processedEventStream.add(updated);
          }
        });
      }

      return saved;
    } catch (e, stack) {
      debugPrint(
        '[EventCoordinator] Error processing incoming native event: $e\n$stack',
      );
      rethrow;
    }
  }

  Future<EventModel?> sendTestEvent({
    required String source,
    required String sender,
    required String message,
    String? title,
    int? simSlot,
    String? packageName,
    String? serviceCenter,
  }) async {
    return await processIncomingNativeEvent({
      'event_id': _uuid.v4(),
      'event_type': '${source}_received',
      'source': source,
      'sender': sender,
      'message': message,
      'title': title,
      'sim_slot': simSlot,
      'package_name': packageName,
      'service_center': serviceCenter,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'is_test': true,
    });
  }
}
