import '../data/local/dao/sim_dao.dart';
import '../domain/models/sim_info_model.dart';
import 'native_service.dart';

class SimService {
  final SimDao _simDao = SimDao();
  final NativeService _nativeService = NativeService.instance;

  Future<List<SimInfoModel>> detectAndSyncSims() async {
    final nativeList = await _nativeService.getSimInfo();
    // Do not remove any local configuration when Android could not provide a
    // subscription list (for example, Phone permission was denied).
    if (nativeList.isEmpty) return await _simDao.getAllSims();
    final now = DateTime.now().millisecondsSinceEpoch;
    final activeSubscriptionIds = activeSubscriptionIdsFromNative(nativeList);

    for (final raw in nativeList) {
      final subId = raw['subscriptionId'] as int? ?? 0;
      if (subId <= 0) continue;
      final slotIndex = raw['slotIndex'] as int? ?? 0;
      final carrier =
          raw['carrierName'] as String? ?? 'Carrier ${slotIndex + 1}';
      final displayName =
          raw['displayName'] as String? ?? 'SIM ${slotIndex + 1}';
      final detectedNumber = raw['number'] as String? ?? '';

      final model = SimInfoModel(
        subscriptionId: subId,
        slotIndex: slotIndex,
        carrierName: carrier,
        defaultName: displayName,
        detectedNumber: detectedNumber,
        numberSource: nativeList.length <= 1 ? 'auto_detect' : 'default',
        updatedAt: now,
      );

      await _simDao.saveOrUpdateSim(model);
    }

    await _simDao.removeInactiveSims(activeSubscriptionIds);

    return await _simDao.getAllSims();
  }

  Future<List<SimInfoModel>> getAllSims() async {
    // Refresh active subscriptions on every screen load. This cleans up old
    // seeded rows such as "SubID: 1" once the real SIM is detected.
    return await detectAndSyncSims();
  }

  Future<void> updateSimConfig({
    required int subscriptionId,
    required String customName,
    required String userPhoneNumber,
    required bool enabled,
    required String numberSource,
  }) async {
    await _simDao.updateSimUserConfig(
      subscriptionId: subscriptionId,
      customName: customName,
      userPhoneNumber: userPhoneNumber,
      enabled: enabled,
      numberSource: numberSource,
    );
  }

  Future<SimInfoModel?> getSimForSlot(int? slotIndex, int? subId) async {
    if (subId != null && subId > 0) {
      final sim = await _simDao.getSimBySubId(subId);
      if (sim != null) return sim;
    }
    if (slotIndex != null && slotIndex >= 0) {
      return await _simDao.getSimBySlot(slotIndex);
    }
    return null;
  }
}

/// Returns only real Android subscription identities; a missing/invalid ID is
/// never allowed to remove an existing configuration row.
Set<int> activeSubscriptionIdsFromNative(
  List<Map<String, dynamic>> nativeList,
) => nativeList
    .map((raw) => raw['subscriptionId'] as int? ?? 0)
    .where((id) => id > 0)
    .toSet();
