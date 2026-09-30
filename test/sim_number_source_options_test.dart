import 'package:flutter_test/flutter_test.dart';
import 'package:msg_to_server/ui/config/sim_config_screen.dart';
import 'package:msg_to_server/services/sim_service.dart';

void main() {
  test('SIM 1 only offers its own auto-detect option', () {
    expect(simNumberSourceOptions(0), [
      ('default', 'Default SIM'),
      ('auto_detect', 'SIM 1 (Auto detect)'),
    ]);
  });

  test('SIM 2 only offers its own auto-detect option', () {
    expect(simNumberSourceOptions(1), [
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
}
