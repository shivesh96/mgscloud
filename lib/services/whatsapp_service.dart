import '../data/local/dao/whatsapp_dao.dart';
import '../domain/models/whatsapp_config_model.dart';
import 'native_service.dart';

class WhatsAppService {
  final WhatsAppDao _whatsAppDao = WhatsAppDao();
  final NativeService _nativeService = NativeService.instance;

  Future<List<WhatsAppConfigModel>> detectAndSyncWhatsApp() async {
    final nativeList = await _nativeService.getInstalledWhatsAppPackages();
    final now = DateTime.now().millisecondsSinceEpoch;

    // If native returns nothing (e.g. emulator without WhatsApp), ensure standard defaults are available for user config
    if (nativeList.isEmpty) {
      final defaultTargets = [
        {'packageName': 'com.whatsapp', 'appName': 'WhatsApp (Primary)', 'isClone': false},
        {'packageName': 'com.whatsapp.w4b', 'appName': 'WhatsApp Business', 'isClone': false},
      ];
      for (final t in defaultTargets) {
        await _whatsAppDao.saveOrUpdateInstance(
          WhatsAppConfigModel(
            packageName: t['packageName'] as String,
            instanceName: t['appName'] as String,
            isClone: t['isClone'] as bool,
            updatedAt: now,
          ),
        );
      }
    } else {
      for (final item in nativeList) {
        final pkg = item['packageName'] as String? ?? '';
        final appName = item['appName'] as String? ?? 'WhatsApp';
        final isClone = item['isClone'] as bool? ?? false;

        if (pkg.isNotEmpty) {
          await _whatsAppDao.saveOrUpdateInstance(
            WhatsAppConfigModel(
              packageName: pkg,
              instanceName: appName,
              isClone: isClone,
              updatedAt: now,
            ),
          );
        }
      }
    }

    return await _whatsAppDao.getAllInstances();
  }

  Future<List<WhatsAppConfigModel>> getAllInstances() async {
    final list = await _whatsAppDao.getAllInstances();
    if (list.isEmpty) {
      return await detectAndSyncWhatsApp();
    }
    return list;
  }

  Future<void> addCustomClone({
    required String packageName,
    required String instanceName,
    required String phoneNumber,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _whatsAppDao.saveOrUpdateInstance(
      WhatsAppConfigModel(
        packageName: packageName.trim(),
        instanceName: instanceName.trim(),
        phoneNumber: phoneNumber.trim(),
        isClone: true,
        enabled: true,
        updatedAt: now,
      ),
    );
  }

  Future<void> updateInstance({
    required int id,
    required String instanceName,
    required String phoneNumber,
    required bool enabled,
  }) async {
    await _whatsAppDao.updateInstanceNumber(
      id: id,
      instanceName: instanceName,
      phoneNumber: phoneNumber,
      enabled: enabled,
    );
  }

  Future<void> deleteInstance(int id) async {
    await _whatsAppDao.deleteInstance(id);
  }

  Future<WhatsAppConfigModel?> findForPackage(String packageName) async {
    return await _whatsAppDao.findConfigByPackage(packageName);
  }
}
