import '../database/app_database.dart';

class SettingsDao {
  Future<Map<String, dynamic>> getSettings() async {
    final db = await AppDatabase.instance.database;
    final results = await db.query(
      'app_settings',
      where: 'id = ?',
      whereArgs: [1],
    );
    if (results.isNotEmpty) {
      return Map<String, dynamic>.from(results.first);
    }
    return {
      'id': 1,
      'server_url': '',
      'protocol': 'HTTP',
      'http_method': 'POST',
      'auth_type': 'NONE',
      'auth_token': '',
      'connection_timeout': 30,
      'retry_count': 3,
      'retry_interval': 15,
      'retention_days': 30,
      'service_enabled': 1,
      'send_filtered_only': 0,
    };
  }

  Future<bool> isServiceEnabled() async {
    final settings = await getSettings();
    return (settings['service_enabled'] as int? ?? 1) == 1;
  }

  Future<void> setServiceEnabled(bool enabled) async {
    final db = await AppDatabase.instance.database;
    await db.update(
      'app_settings',
      {'service_enabled': enabled ? 1 : 0},
      where: 'id = ?',
      whereArgs: [1],
    );
  }

  Future<bool> isSendFilteredOnly() async {
    final settings = await getSettings();
    return (settings['send_filtered_only'] as int? ?? 0) == 1;
  }

  Future<void> setSendFilteredOnly(bool enabled) async {
    final db = await AppDatabase.instance.database;
    await db.update(
      'app_settings',
      {'send_filtered_only': enabled ? 1 : 0},
      where: 'id = ?',
      whereArgs: [1],
    );
  }

  Future<void> updateSettings(Map<String, dynamic> settings) async {
    final db = await AppDatabase.instance.database;
    final clean = Map<String, dynamic>.from(settings);
    clean['id'] = 1;

    final existing = await db.query(
      'app_settings',
      where: 'id = ?',
      whereArgs: [1],
    );
    if (existing.isNotEmpty) {
      await db.update('app_settings', clean, where: 'id = ?', whereArgs: [1]);
    } else {
      await db.insert('app_settings', clean);
    }
  }
}
