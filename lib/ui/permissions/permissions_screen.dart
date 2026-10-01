import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../services/native_service.dart';

class PermissionsScreen extends StatefulWidget {
  const PermissionsScreen({super.key});

  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends State<PermissionsScreen> {
  final NativeService _nativeService = NativeService.instance;

  bool _smsGranted = false;
  bool _phoneGranted = false;
  bool _notificationPostGranted = false;
  bool _notificationListenerGranted = false;
  bool _batteryOptimizationIgnored = false;
  String _manufacturer = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    setState(() => _isLoading = true);

    final sms = await Permission.sms.isGranted;
    final phone = await Permission.phone.isGranted;
    final notifPost = await Permission.notification.isGranted;
    final notifListener = await _nativeService.isNotificationListenerPermissionGranted();
    final battery = await _nativeService.isBatteryOptimizationIgnored();
    final manufacturer = await _nativeService.getDeviceManufacturer();

    setState(() {
      _smsGranted = sms;
      _phoneGranted = phone;
      _notificationPostGranted = notifPost;
      _notificationListenerGranted = notifListener;
      _batteryOptimizationIgnored = battery;
      _manufacturer = manufacturer;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Permissions & Access'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _checkPermissions,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildInfoBanner(),
                const SizedBox(height: 16),
                _buildPermissionTile(
                  icon: Icons.sms_outlined,
                  title: 'SMS Access',
                  description: 'Required to detect and read incoming SMS messages and OTPs.',
                  isGranted: _smsGranted,
                  onAction: () async {
                    await Permission.sms.request();
                    _checkPermissions();
                  },
                ),
                _buildPermissionTile(
                  icon: Icons.sim_card_outlined,
                  title: 'Phone & SIM State',
                  description: 'Required to detect active SIM cards, carrier names, and SIM slots.',
                  isGranted: _phoneGranted,
                  onAction: () async {
                    await Permission.phone.request();
                    _checkPermissions();
                  },
                ),
                _buildPermissionTile(
                  icon: Icons.notifications_active_outlined,
                  title: 'Notification Access (Listener)',
                  description: 'Required to intercept WhatsApp, Telegram, and other app notifications.',
                  isGranted: _notificationListenerGranted,
                  actionLabel: 'Open Settings',
                  onAction: () async {
                    await _nativeService.openNotificationListenerSettings();
                    _checkPermissions();
                  },
                ),
                _buildPermissionTile(
                  icon: Icons.notifications_none_outlined,
                  title: 'Show Notifications',
                  description: 'Required for Android 13+ foreground service status banner.',
                  isGranted: _notificationPostGranted,
                  onAction: () async {
                    await Permission.notification.request();
                    _checkPermissions();
                  },
                ),
                _buildPermissionTile(
                  icon: Icons.battery_charging_full_outlined,
                  title: 'Ignore Battery Optimizations',
                  description: 'Prevents Android OS from killing the forwarding service in the background.',
                  isGranted: _batteryOptimizationIgnored,
                  actionLabel: 'Disable Optimization',
                  onAction: () async {
                    await _nativeService.requestIgnoreBatteryOptimizations();
                    _checkPermissions();
                  },
                ),
                if (_isAggressiveOem)
                  _buildPermissionTile(
                    icon: Icons.power_settings_new_outlined,
                    title: _oemTitle,
                    description:
                        'Crucial: ${_manufacturer.toUpperCase()} power management aggressively kills background services when the screen locks. Enable AutoStart and set Background activity to unrestricted.',
                    isGranted: false,
                    actionLabel: 'Open AutoStart Settings',
                    onAction: () async {
                      await _nativeService.openAutoStartSettings();
                    },
                  ),
              ],
            ),
    );
  }

  bool get _isAggressiveOem {
    final m = _manufacturer.toLowerCase();
    return m.contains('xiaomi') ||
        m.contains('redmi') ||
        m.contains('poco') ||
        m.contains('samsung') ||
        m.contains('huawei') ||
        m.contains('honor') ||
        m.contains('oppo') ||
        m.contains('realme') ||
        m.contains('vivo') ||
        m.contains('iqoo') ||
        m.contains('oneplus');
  }

  String get _oemTitle {
    final m = _manufacturer.toLowerCase();
    if (m.contains('xiaomi') || m.contains('redmi') || m.contains('poco')) {
      return 'Xiaomi / MIUI AutoStart';
    } else if (m.contains('samsung')) {
      return 'Samsung Device Care & Battery';
    } else if (m.contains('huawei') || m.contains('honor')) {
      return 'Huawei App Launch / Startup';
    } else if (m.contains('oppo') || m.contains('realme')) {
      return 'Oppo / Realme Auto-Launch';
    } else if (m.contains('vivo') || m.contains('iqoo')) {
      return 'Vivo / iQOO Background Power';
    } else if (m.contains('oneplus')) {
      return 'OnePlus App Auto-Launch';
    }
    return 'OEM Background Management';
  }

  Widget _buildInfoBanner() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.security, color: Colors.blue.shade700),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Message Cloud operates transparently. Permissions are required to forward events per your configuration.',
              style: TextStyle(fontSize: 13, color: Colors.blue.shade900),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionTile({
    required IconData icon,
    required String title,
    required String description,
    required bool isGranted,
    String? actionLabel,
    required VoidCallback onAction,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 28, color: isGranted ? Colors.green : Colors.orange),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isGranted ? Colors.green.shade100 : Colors.red.shade100,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    isGranted ? 'GRANTED' : 'REQUIRED',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: isGranted ? Colors.green.shade800 : Colors.red.shade800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              description,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
            if (!isGranted) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton(
                  onPressed: onAction,
                  child: Text(actionLabel ?? 'Grant Permission'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
