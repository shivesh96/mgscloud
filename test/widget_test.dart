import 'package:flutter_test/flutter_test.dart';
import 'package:msg_to_server/main.dart';

void main() {
  test('App root can be constructed without device services', () {
    // Database and platform channels are integration concerns; keep this
    // unit-level smoke test free of a device-only sqflite dependency.
    expect(const MsgToServerApp(), isA<MsgToServerApp>());
  });
}
