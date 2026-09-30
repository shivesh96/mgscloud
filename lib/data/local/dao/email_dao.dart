import '../database/app_database.dart';
import '../../../domain/models/email_config_model.dart';

import 'package:sqflite/sqflite.dart';

class EmailDao {
  Future<List<EmailConfigModel>> getEmailConfigs() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query('email_accounts', orderBy: 'id ASC');
    return rows.map(EmailConfigModel.fromMap).toList();
  }

  Future<List<EmailConfigModel>> getEnabledEmailConfigs() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'email_accounts',
      where: 'enabled = 1',
      orderBy: 'id ASC',
    );
    return rows.map(EmailConfigModel.fromMap).toList();
  }

  // Kept for old callers that only need the first configured account.
  Future<EmailConfigModel> getEmailConfig() async {
    final configs = await getEmailConfigs();
    return configs.isNotEmpty
        ? configs.first
        : EmailConfigModel(updatedAt: DateTime.now().millisecondsSinceEpoch);
  }

  Future<EmailConfigModel> saveEmailConfig(EmailConfigModel config) async {
    final db = await AppDatabase.instance.database;
    final values = config.toMap();
    final int id;
    if (config.id == null) {
      id = await db.insert('email_accounts', values);
    } else {
      await db.update(
        'email_accounts',
        values,
        where: 'id = ?',
        whereArgs: [config.id],
      );
      id = config.id!;
    }
    return config.copyWith(id: id);
  }

  Future<void> deleteEmailConfig(int id) async {
    final db = await AppDatabase.instance.database;
    await db.transaction((txn) async {
      await txn.delete(
        'processed_email_events',
        where: 'account_id = ?',
        whereArgs: [id],
      );
      await txn.delete('email_accounts', where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<void> updateLastSynced(int accountId, int timestamp) async {
    final db = await AppDatabase.instance.database;
    await db.update(
      'email_accounts',
      {
        'last_synced_at': timestamp,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [accountId],
    );
  }

  Future<bool> isEmailProcessed(int accountId, int uidValidity, int uid) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'processed_email_events',
      where: 'account_id = ? AND uid_validity = ? AND uid = ?',
      whereArgs: [accountId, uidValidity, uid],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<void> markEmailProcessed(
    int accountId,
    int uidValidity,
    int uid,
    String messageId,
  ) async {
    final db = await AppDatabase.instance.database;
    await db.insert('processed_email_events', {
      'account_id': accountId,
      'uid_validity': uidValidity,
      'uid': uid,
      'message_id': messageId,
      'processed_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }
}
