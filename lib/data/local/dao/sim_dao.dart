import '../database/app_database.dart';
import '../../../domain/models/sim_info_model.dart';

class SimDao {
  Future<List<SimInfoModel>> getAllSims() async {
    final db = await AppDatabase.instance.database;
    final results = await db.query('sim_config', orderBy: 'slot_index ASC');
    return results.map((m) => SimInfoModel.fromMap(m)).toList();
  }

  Future<SimInfoModel?> getSimBySlot(int slotIndex) async {
    final db = await AppDatabase.instance.database;
    final results = await db.query(
      'sim_config',
      where: 'slot_index = ?',
      whereArgs: [slotIndex],
      limit: 1,
    );
    if (results.isNotEmpty) {
      return SimInfoModel.fromMap(results.first);
    }
    return null;
  }

  Future<SimInfoModel?> getSimBySubId(int subId) async {
    final db = await AppDatabase.instance.database;
    final results = await db.query(
      'sim_config',
      where: 'subscription_id = ?',
      whereArgs: [subId],
      limit: 1,
    );
    if (results.isNotEmpty) {
      return SimInfoModel.fromMap(results.first);
    }
    return null;
  }

  Future<void> saveOrUpdateSim(SimInfoModel sim) async {
    final db = await AppDatabase.instance.database;
    final existing = await db.query(
      'sim_config',
      where: 'subscription_id = ?',
      whereArgs: [sim.subscriptionId],
      limit: 1,
    );

    if (existing.isNotEmpty) {
      // Preserve existing custom_name / user_phone_number if incoming is blank,
      // and preserve user-configured numberSource and enabled states across native scans.
      final existingModel = SimInfoModel.fromMap(existing.first);
      final merged = sim.copyWith(
        customName: sim.customName.isNotEmpty
            ? sim.customName
            : existingModel.customName,
        userPhoneNumber: sim.userPhoneNumber.isNotEmpty
            ? sim.userPhoneNumber
            : existingModel.userPhoneNumber,
        numberSource: existingModel.numberSource,
        enabled: existingModel.enabled,
      );
      await db.update(
        'sim_config',
        merged.toMap(),
        where: 'subscription_id = ?',
        whereArgs: [sim.subscriptionId],
      );
    } else {
      await db.insert('sim_config', sim.toMap());
    }
  }

  /// The system subscription list is authoritative. This removes stale rows
  /// left by old placeholder configuration or a removed SIM, but is never
  /// called for an empty/unknown native list.
  Future<void> removeInactiveSims(Set<int> activeSubscriptionIds) async {
    if (activeSubscriptionIds.isEmpty) return;
    final db = await AppDatabase.instance.database;
    final placeholders = List.filled(
      activeSubscriptionIds.length,
      '?',
    ).join(',');
    await db.delete(
      'sim_config',
      where: 'subscription_id NOT IN ($placeholders)',
      whereArgs: activeSubscriptionIds.toList(),
    );
  }

  Future<void> updateSimUserConfig({
    required int subscriptionId,
    required String customName,
    required String userPhoneNumber,
    required bool enabled,
    required String numberSource,
  }) async {
    final db = await AppDatabase.instance.database;
    await db.update(
      'sim_config',
      {
        'custom_name': customName,
        'user_phone_number': userPhoneNumber,
        'enabled': enabled ? 1 : 0,
        'number_source': numberSource,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'subscription_id = ?',
      whereArgs: [subscriptionId],
    );
  }
}
