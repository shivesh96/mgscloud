import 'package:permission_handler/permission_handler.dart';

import 'native_service.dart';

/// Mandatory runtime prerequisites for SMS/email forwarding. Notification
/// listener access is intentionally excluded because it is only needed for
/// optional WhatsApp capture.
class PermissionGateService {
  static final PermissionGateService instance = PermissionGateService._init();
  PermissionGateService._init();

  Future<bool> hasMandatoryPermissions() async =>
      await Permission.sms.isGranted &&
      await Permission.phone.isGranted &&
      await Permission.notification.isGranted &&
      await NativeService.instance.isBatteryOptimizationIgnored();

  /// Requests runtime permissions in sequence. Android ultimately owns the
  /// choice, so a permanent denial is represented as false and the UI blocks
  /// setup until the user grants it in system settings.
  Future<bool> requestMandatoryPermissions() async {
    if (!await Permission.sms.isGranted) await Permission.sms.request();
    if (!await Permission.phone.isGranted) await Permission.phone.request();
    if (!await Permission.notification.isGranted)
      await Permission.notification.request();
    if (!await NativeService.instance.isBatteryOptimizationIgnored()) {
      await NativeService.instance.requestIgnoreBatteryOptimizations();
    }
    return hasMandatoryPermissions();
  }
}
