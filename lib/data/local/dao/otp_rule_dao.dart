import '../database/app_database.dart';
import '../../../domain/models/otp_rule_model.dart';

class OtpRuleDao {

  Future<int> upsertRuleFromServer(OtpRuleModel rule) async {
    final db = await AppDatabase.instance.database;
    final map = rule.toMap();
    map.remove('id'); // do not overwrite local auto-increment primary key
    
    // Ensure column existence runtime safety
    try {
      await db.execute('ALTER TABLE otp_rules ADD COLUMN server_id INTEGER');
    } catch (_) {}
    try {
      await db.execute('ALTER TABLE otp_rules ADD COLUMN request_body_sample TEXT');
    } catch (_) {}
    try {
      await db.execute('ALTER TABLE otp_rules ADD COLUMN raw_data TEXT');
    } catch (_) {}

    // Check by server_id or rule_name
    List<Map<String, dynamic>> existing = [];
    try {
      if (rule.serverId != null) {
        existing = await db.query('otp_rules', where: 'server_id = ?', whereArgs: [rule.serverId]);
      }
    } catch (_) {}

    if (existing.isEmpty) {
      try {
        existing = await db.query('otp_rules', where: 'rule_name = ?', whereArgs: [rule.ruleName]);
      } catch (_) {}
    }

    if (existing.isNotEmpty) {
      final localId = existing.first['id'] as int;
      await db.update('otp_rules', map, where: 'id = ?', whereArgs: [localId]);
      return localId;
    } else {
      return await db.insert('otp_rules', map);
    }
  }

  Future<OtpRuleModel?> getRuleById(int id) async {
    final db = await AppDatabase.instance.database;
    final results = await db.query('otp_rules', where: 'id = ?', whereArgs: [id]);
    if (results.isNotEmpty) {
      return OtpRuleModel.fromMap(results.first);
    }
    return null;
  }

  Future<OtpRuleModel?> getRuleByName(String name) async {
    final db = await AppDatabase.instance.database;
    final results = await db.query('otp_rules', where: 'rule_name = ?', whereArgs: [name]);
    if (results.isNotEmpty) {
      return OtpRuleModel.fromMap(results.first);
    }
    return null;
  }

  Future<void> updateServerId(int localId, int serverId) async {
    final db = await AppDatabase.instance.database;
    await db.update('otp_rules', {'server_id': serverId}, where: 'id = ?', whereArgs: [localId]);
  }

  Future<List<OtpRuleModel>> getAllRules() async {
    final db = await AppDatabase.instance.database;
    final results = await db.query('otp_rules', orderBy: 'id ASC');
    return results.map((r) => OtpRuleModel.fromMap(r)).toList();
  }

  Future<List<OtpRuleModel>> getEnabledRules() async {
    final db = await AppDatabase.instance.database;
    final results = await db.query(
      'otp_rules',
      where: 'enabled = 1',
      orderBy: 'id ASC',
    );
    return results.map((r) => OtpRuleModel.fromMap(r)).toList();
  }

  Future<List<OtpRuleModel>> getActiveRules() async => getEnabledRules();

  Future<int> insertRule(OtpRuleModel rule) async {
    final db = await AppDatabase.instance.database;
    return await db.insert('otp_rules', rule.toMap());
  }

  Future<void> updateRule(OtpRuleModel rule) async {
    if (rule.id == null) return;
    final db = await AppDatabase.instance.database;
    await db.update(
      'otp_rules',
      rule.toMap(),
      where: 'id = ?',
      whereArgs: [rule.id],
    );
  }

  Future<void> deleteRule(int id) async {
    final db = await AppDatabase.instance.database;
    await db.delete('otp_rules', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> toggleRule(int id, bool enabled) async {
    final db = await AppDatabase.instance.database;
    await db.update(
      'otp_rules',
      {
        'enabled': enabled ? 1 : 0,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
