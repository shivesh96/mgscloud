import '../database/app_database.dart';
import '../../../domain/models/whatsapp_config_model.dart';

class WhatsAppDao {
  Future<List<WhatsAppConfigModel>> getAllInstances() async {
    final db = await AppDatabase.instance.database;
    final results = await db.query('whatsapp_config', orderBy: 'id ASC');
    return results.map((m) => WhatsAppConfigModel.fromMap(m)).toList();
  }

  Future<List<WhatsAppConfigModel>> getAllConfigs() => getAllInstances();

  Future<WhatsAppConfigModel?> findConfigByPackage(String packageName) async {
    final db = await AppDatabase.instance.database;
    final results = await db.query(
      'whatsapp_config',
      where: 'package_name = ?',
      whereArgs: [packageName],
      limit: 1,
    );
    if (results.isNotEmpty) {
      return WhatsAppConfigModel.fromMap(results.first);
    }
    return null;
  }

  Future<void> saveOrUpdateInstance(WhatsAppConfigModel config) async {
    final db = await AppDatabase.instance.database;
    if (config.id != null) {
      await db.update(
        'whatsapp_config',
        config.toMap(),
        where: 'id = ?',
        whereArgs: [config.id],
      );
    } else {
      // Check if package exists
      final existing = await db.query(
        'whatsapp_config',
        where: 'package_name = ?',
        whereArgs: [config.packageName],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        final existingModel = WhatsAppConfigModel.fromMap(existing.first);
        final merged = config.copyWith(
          id: existingModel.id,
          phoneNumber: config.phoneNumber.isNotEmpty ? config.phoneNumber : existingModel.phoneNumber,
          instanceName: config.instanceName.isNotEmpty ? config.instanceName : existingModel.instanceName,
        );
        await db.update(
          'whatsapp_config',
          merged.toMap(),
          where: 'id = ?',
          whereArgs: [existingModel.id],
        );
      } else {
        await db.insert('whatsapp_config', config.toMap());
      }
    }
  }

  Future<void> updateInstanceNumber({
    required int id,
    required String instanceName,
    required String phoneNumber,
    required bool enabled,
  }) async {
    final db = await AppDatabase.instance.database;
    await db.update(
      'whatsapp_config',
      {
        'instance_name': instanceName,
        'phone_number': phoneNumber,
        'enabled': enabled ? 1 : 0,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteInstance(int id) async {
    final db = await AppDatabase.instance.database;
    await db.delete('whatsapp_config', where: 'id = ?', whereArgs: [id]);
  }
}
