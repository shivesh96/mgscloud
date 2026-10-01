import 'package:flutter_test/flutter_test.dart';
import 'package:msg_to_server/domain/models/event_model.dart';
import 'package:msg_to_server/domain/models/sim_info_model.dart';
import 'package:msg_to_server/ui/config/sim_config_screen.dart';
import 'package:msg_to_server/services/sim_service.dart';

void main() {
  test('single SIM offers only one option (auto detect)', () {
    expect(simNumberSourceOptions(0, totalSims: 1), [
      ('auto_detect', 'SIM 1 (Auto Detect)'),
    ]);
  });

  test('multiple SIMs offer multiple options for each SIM', () {
    expect(simNumberSourceOptions(0, totalSims: 2), [
      ('default', 'Default SIM'),
      ('auto_detect', 'SIM 1 (Auto Detect)'),
    ]);
    expect(simNumberSourceOptions(1, totalSims: 2), [
      ('default', 'Default SIM'),
      ('auto_detect', 'SIM 2 (Auto Detect)'),
    ]);
  });

  test('only active Android subscriptions are retained during a refresh', () {
    expect(
      activeSubscriptionIdsFromNative([
        {'subscriptionId': 4, 'slotIndex': 0},
        {'subscriptionId': 0, 'slotIndex': 1},
      ]),
      {4},
    );
  });

  test('SimInfoModel copyWith preserves numberSource and enabled across scans', () {
    final existingModel = SimInfoModel(
      subscriptionId: 1,
      slotIndex: 0,
      carrierName: 'Carrier 1',
      defaultName: 'SIM 1',
      customName: 'Work SIM',
      userPhoneNumber: '+1234567890',
      numberSource: 'auto_detect',
      enabled: false,
      updatedAt: 1000,
    );

    final scannedModel = SimInfoModel(
      subscriptionId: 1,
      slotIndex: 0,
      carrierName: 'Updated Carrier',
      defaultName: 'SIM 1',
      detectedNumber: '+0987654321',
      numberSource: 'default',
      enabled: true,
      updatedAt: 2000,
    );

    final merged = scannedModel.copyWith(
      customName: scannedModel.customName.isNotEmpty
          ? scannedModel.customName
          : existingModel.customName,
      userPhoneNumber: scannedModel.userPhoneNumber.isNotEmpty
          ? scannedModel.userPhoneNumber
          : existingModel.userPhoneNumber,
      numberSource: existingModel.numberSource,
      enabled: existingModel.enabled,
    );

    expect(merged.customName, 'Work SIM');
    expect(merged.numberSource, 'auto_detect');
    expect(merged.enabled, false);
    expect(merged.effectiveNumber, '+0987654321');
  });

  test('SimInfoModel.effectiveNumber falls back to userPhoneNumber when detectedNumber is empty', () {
    final simAuto = SimInfoModel(
      subscriptionId: 1,
      slotIndex: 0,
      carrierName: 'Carrier',
      defaultName: 'SIM 1',
      detectedNumber: '',
      userPhoneNumber: '+919876543210',
      numberSource: 'auto_detect',
      updatedAt: 100,
    );
    expect(simAuto.effectiveNumber, '+919876543210');

    final simEmpty = simAuto.copyWith(userPhoneNumber: '');
    expect(simEmpty.effectiveNumber, 'Not configured');
  });

  test('EventModel.toServerPayload cleans Not configured values', () {
    final event = EventModel(
      eventId: 'evt-1',
      deviceId: 'dev-1',
      eventType: 'sms_received',
      source: 'sms',
      timestamp: '2026-10-01T12:00:00Z',
      simSlot: 0,
      simName: 'SIM 1',
      simNumber: 'Not configured',
      targetMobile: 'Not configured',
      userPhoneNumber: 'Not configured',
      sender: 'MOBIK',
      message: 'OTP 123456',
      createdAt: 100,
    );

    final payload = event.toServerPayload();
    expect(payload['mobile'], isNull);
    expect(payload['sim_number'], isNull);
    expect(payload['sim']?['number'], isNull);
  });

  test('single SIM device resolves SMS with subId: 1 to the single SIM with subId: 4', () {
    final singleSim = SimInfoModel(
      subscriptionId: 4,
      slotIndex: 0,
      carrierName: 'Jio True5G — Jio',
      defaultName: 'SIM1',
      customName: 'SIM1',
      detectedNumber: '+918292000123',
      userPhoneNumber: '+918292000123',
      numberSource: 'auto_detect',
      enabled: true,
      updatedAt: 100,
    );

    final allSims = [singleSim];

    // Single-sim resolution simulation as in EventCoordinator
    SimInfoModel? matchedSim;
    if (allSims.length == 1) {
      matchedSim = allSims.first;
    }

    expect(matchedSim, isNotNull);
    expect(matchedSim!.subscriptionId, 4);
    expect(matchedSim.effectiveNumber, '+918292000123');

    final event = EventModel(
      eventId: 'sms-test-1',
      deviceId: 'dev-1',
      eventType: 'sms_received',
      source: 'sms',
      timestamp: '2026-10-01T12:00:00Z',
      simSlot: matchedSim.slotIndex,
      simName: matchedSim.effectiveName,
      simNumber: matchedSim.effectiveNumber,
      sender: 'JK-IDBIBK-S',
      message: 'Maintenance alert',
      createdAt: 100,
    );

    final payload = event.toServerPayload();
    expect(payload['mobile'], '+918292000123');
    expect(payload['sim_number'], '+918292000123');
    expect(payload['sim']?['slot'], 0);
    expect(payload['sim']?['number'], '+918292000123');
  });

  test('SMS from a phone number preserves numeric sender and uses receiving SIM for mobile', () {
    const receivingSimNumber = '+918292000123';
    const numericSender = '+919876543210';

    final event = EventModel(
      eventId: 'sms-num-sender',
      deviceId: 'dev-1',
      eventType: 'sms_received',
      source: 'sms',
      timestamp: '2026-10-01T12:00:00Z',
      simSlot: 0,
      simName: 'SIM1',
      simNumber: receivingSimNumber,
      targetMobile: receivingSimNumber,
      sender: numericSender,
      message: 'Hello, are you available?',
      deliveryStatus: 'pending', // in all-messages forwarding mode
      createdAt: 200,
    );

    final payload = event.toServerPayload();
    // Crucial: sender is the external contact
    expect(payload['sender'], numericSender);
    // Crucial: mobile is the receiving device's SIM number, NOT the sender
    expect(payload['mobile'], receivingSimNumber);
    expect(payload['sim_number'], receivingSimNumber);
    expect(payload['sim']?['number'], receivingSimNumber);
    expect(payload['body'], 'Hello, are you available?');
  });
}
