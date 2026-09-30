import 'package:flutter/material.dart';
import '../../domain/models/whatsapp_config_model.dart';
import '../../services/native_service.dart';
import '../../services/whatsapp_service.dart';

class WhatsAppConfigScreen extends StatefulWidget {
  const WhatsAppConfigScreen({super.key});

  @override
  State<WhatsAppConfigScreen> createState() => _WhatsAppConfigScreenState();
}

class _WhatsAppConfigScreenState extends State<WhatsAppConfigScreen> with WidgetsBindingObserver {
  final WhatsAppService _whatsAppService = WhatsAppService();
  final NativeService _nativeService = NativeService.instance;
  List<WhatsAppConfigModel> _instances = [];
  bool _isLoading = true;
  bool _notificationListenerGranted = false;
  final Map<int, TextEditingController> _nameControllers = {};
  final Map<int, TextEditingController> _numberControllers = {};
  final Map<int, bool> _enabledStates = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkNotificationPermissions();
    _loadInstances();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkNotificationPermissions();
    }
  }

  Future<void> _checkNotificationPermissions() async {
    final listener = await _nativeService.isNotificationListenerPermissionGranted();
    if (mounted) {
      setState(() {
        _notificationListenerGranted = listener;
      });
    }
  }

  Future<void> _loadInstances() async {
    setState(() => _isLoading = true);
    await _checkNotificationPermissions();
    final list = await _whatsAppService.getAllInstances();
    _initControllers(list);
    setState(() {
      _instances = list;
      _isLoading = false;
    });
  }

  Future<void> _scanWhatsAppApps() async {
    setState(() => _isLoading = true);
    await _checkNotificationPermissions();
    final list = await _whatsAppService.detectAndSyncWhatsApp();
    _initControllers(list);
    setState(() {
      _instances = list;
      _isLoading = false;
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Found ${list.length} WhatsApp app(s) on device'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  void _initControllers(List<WhatsAppConfigModel> list) {
    for (final item in list) {
      final id = item.id ?? item.packageName.hashCode;
      _nameControllers[id] ??= TextEditingController(text: item.instanceName);
      _numberControllers[id] ??= TextEditingController(text: item.phoneNumber);
      _enabledStates[id] ??= item.enabled;
    }
  }

  Future<void> _saveInstance(WhatsAppConfigModel item) async {
    final id = item.id;
    if (id == null) return;
    final name = _nameControllers[id]?.text.trim() ?? item.instanceName;
    final number = _numberControllers[id]?.text.trim() ?? '';
    final enabled = _enabledStates[id] ?? true;

    await _whatsAppService.updateInstance(
      id: id,
      instanceName: name,
      phoneNumber: number,
      enabled: enabled,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Saved $name with number: ${number.isNotEmpty ? number : "Not set"}'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _showAddCloneDialog() async {
    final pkgCtrl = TextEditingController(text: 'com.whatsapp.clone');
    final nameCtrl = TextEditingController(text: 'Cloned WhatsApp');
    final numCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add WhatsApp Clone App'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Instance Label',
                  hintText: 'e.g. Dual Messenger, Parallel WhatsApp',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: pkgCtrl,
                decoration: const InputDecoration(
                  labelText: 'Package Name',
                  hintText: 'e.g. com.whatsapp, com.parallel.space',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: numCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Assigned Phone Number',
                  hintText: 'e.g. +91 98765 43210',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (pkgCtrl.text.trim().isNotEmpty && nameCtrl.text.trim().isNotEmpty) {
                await _whatsAppService.addCustomClone(
                  packageName: pkgCtrl.text.trim(),
                  instanceName: nameCtrl.text.trim(),
                  phoneNumber: numCtrl.text.trim(),
                );
                if (mounted) {
                  Navigator.pop(ctx);
                  _loadInstances();
                }
              }
            },
            child: const Text('Add Clone'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('WhatsApp Configuration'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Scan WhatsApp Apps',
            onPressed: _scanWhatsAppApps,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddCloneDialog,
        icon: const Icon(Icons.add),
        label: const Text('Add Clone App'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
              children: [
                _buildPermissionBanner(),
                if (_instances.isEmpty)
                  _buildEmptyState()
                else
                  ..._instances.map((item) => _buildInstanceCard(item)),
              ],
            ),
    );
  }

  Widget _buildPermissionBanner() {
    if (!_notificationListenerGranted) {
      return Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.amber.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.amber.shade300),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.notifications_off_outlined, color: Colors.amber.shade800, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Notification Listener Permission Required',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.amber.shade900,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Android Notification Access is currently disabled. The app cannot intercept incoming WhatsApp or WhatsApp Clone notifications until permission is enabled in device settings.',
              style: TextStyle(fontSize: 12, color: Colors.amber.shade900),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber.shade800,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                ),
                icon: const Icon(Icons.settings, size: 16),
                label: const Text('Open Notification Access Settings'),
                onPressed: () async {
                  await _nativeService.openNotificationListenerSettings();
                  await _checkNotificationPermissions();
                },
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle, color: Colors.green.shade700, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Notification Listener Access Active ✓',
              style: TextStyle(
                fontSize: 12,
                color: Colors.green.shade900,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          InkWell(
            onTap: _checkNotificationPermissions,
            child: Padding(
              padding: const EdgeInsets.all(4.0),
              child: Text(
                'Re-check',
                style: TextStyle(fontSize: 12, color: Colors.green.shade800, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.chat_bubble_outline, size: 72, color: Colors.green),
            const SizedBox(height: 16),
            const Text(
              'No WhatsApp Apps Detected',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Tap below to scan for installed WhatsApp, Business, Dual Messenger, or Parallel clones.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _scanWhatsAppApps,
              icon: const Icon(Icons.refresh),
              label: const Text('Scan Installed Apps'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInstanceCard(WhatsAppConfigModel item) {
    final id = item.id ?? item.packageName.hashCode;
    final nameCtrl = _nameControllers[id];
    final numCtrl = _numberControllers[id];
    final isEnabled = _enabledStates[id] ?? true;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: Colors.green.shade100,
                  child: const Icon(Icons.chat, color: Colors.green),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              item.instanceName,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (item.isClone) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.orange.shade100,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'CLONE / DUAL',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.orange.shade900,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      Text(
                        item.packageName,
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: isEnabled,
                  activeColor: Colors.green,
                  onChanged: (val) {
                    setState(() {
                      _enabledStates[id] = val;
                    });
                  },
                ),
              ],
            ),
            const Divider(height: 24),
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Instance Label',
                hintText: 'e.g. WhatsApp Personal, WhatsApp Work',
                prefixIcon: Icon(Icons.badge_outlined),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: numCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Set WhatsApp Phone Number',
                hintText: 'e.g. +91 98765 43210',
                prefixIcon: Icon(Icons.phone_android_outlined),
                border: OutlineInputBorder(),
                helperText: 'Attached to server payload for incoming notifications',
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (item.isClone && item.id != null)
                  TextButton.icon(
                    onPressed: () async {
                      await _whatsAppService.deleteInstance(item.id!);
                      _loadInstances();
                    },
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    label: const Text('Delete', style: TextStyle(color: Colors.red)),
                  ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () => _saveInstance(item),
                  icon: const Icon(Icons.save),
                  label: const Text('Save WhatsApp Config'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade50),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final c in _nameControllers.values) {
      c.dispose();
    }
    for (final c in _numberControllers.values) {
      c.dispose();
    }
    super.dispose();
  }
}
