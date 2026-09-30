import 'package:flutter_test/flutter_test.dart';
import 'package:msg_to_server/domain/models/email_config_model.dart';

void main() {
  test('email account serialization preserves its independent account id', () {
    final account = EmailConfigModel(
      id: 7,
      emailAddress: 'work@example.com',
      username: 'work@example.com',
      password: 'app-password',
      enabled: true,
      updatedAt: 123,
    );

    final restored = EmailConfigModel.fromMap(account.toMap());
    expect(restored.id, 7);
    expect(restored.accountKey, '7');
    expect(restored.enabled, isTrue);
  });

  test('new account keeps a null id until persistence assigns one', () {
    final account = EmailConfigModel(updatedAt: 1);
    expect(account.id, isNull);
    expect(account.copyWith(id: 8).accountKey, '8');
  });
}
