import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../domain/models/sim_info_model.dart';
import '../../services/sim_service.dart';

class SimConfigScreen extends StatefulWidget {
  const SimConfigScreen({super.key});

  @override
  State<SimConfigScreen> createState() => _SimConfigScreenState();
}

class _SimConfigScreenState extends State<SimConfigScreen> {
  final SimService _simService = SimService();
  List<SimInfoModel> _sims = [];
  bool _isLoading = true;
  bool _phoneGranted = false;
  bool _smsGranted = false;

  final Map<int, TextEditingController> _nameControllers = {};
  final Map<int, TextEditingController> _numberControllers = {};
  final Map<int, bool> _enabledStates = {};
  final Map<int, String> _numberSources = {};

  @override
  void initState() {
    super.initState();
    _checkSimPermissions();
    _loadSims();
  }

  Future<void> _checkSimPermissions() async {
    final phone = await Permission.phone.isGranted;
    final sms = await Permission.sms.isGranted;
    if (mounted) {
      setState(() {
        _phoneGranted = phone;
        _smsGranted = sms;
      });
    }
  }

  Future<void> _loadSims() async {
    setState(() => _isLoading = true);
    await _checkSimPermissions();
    final list = await _simService.getAllSims();
    _initControllers(list);
    setState(() {
      _sims = list;
      _isLoading = false;
    });
  }

  Future<void> _detectSims() async {
    setState(() => _isLoading = true);
    await _checkSimPermissions();
    final list = await _simService.detectAndSyncSims();
    _initControllers(list);
    setState(() {
      _sims = list;
      _isLoading = false;
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Detected ${list.length} SIM card(s) from device'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  void _initControllers(List<SimInfoModel> list) {
    for (final sim in list) {
      _nameControllers[sim.subscriptionId] ??= TextEditingController(
        text: sim.customName.isNotEmpty ? sim.customName : sim.defaultName,
      );
      _numberControllers[sim.subscriptionId] ??= TextEditingController(
        text: sim.userPhoneNumber.isNotEmpty
            ? sim.userPhoneNumber
            : sim.detectedNumber,
      );
      _enabledStates[sim.subscriptionId] ??= sim.enabled;
      _numberSources[sim.subscriptionId] ??= sim.numberSource;
    }
  }

  Future<void> _saveSim(SimInfoModel sim) async {
    final subId = sim.subscriptionId;
    final name = _nameControllers[subId]?.text.trim() ?? '';
    final number = _numberControllers[subId]?.text.trim() ?? '';
    final enabled = _enabledStates[subId] ?? true;
    final numberSource = _numberSources[subId] ?? 'default';

    await _simService.updateSimConfig(
      subscriptionId: subId,
      customName: name,
      userPhoneNumber: number,
      enabled: enabled,
      numberSource: numberSource,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Saved configuration for SIM ${sim.slotIndex + 1} ($name)',
          ),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SIM Configuration'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Detect SIMs',
            onPressed: _detectSims,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildPermissionBanner(),
                if (_sims.isEmpty)
                  _buildEmptyState()
                else
                  ..._sims.map((sim) => _buildSimCard(sim)),
              ],
            ),
    );
  }

  Widget _buildPermissionBanner() {
    final bool missingAny = !_phoneGranted || !_smsGranted;

    if (missingAny) {
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
                Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.amber.shade800,
                  size: 22,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Permission Required for SIM Management',
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
              !_phoneGranted && !_smsGranted
                  ? 'Phone State and SMS permissions are disabled. The app cannot read active SIM slots, carrier names, or incoming SMS.'
                  : !_phoneGranted
                  ? 'Phone State permission is missing. Android cannot provide active SIM card subscriptions.'
                  : 'SMS permission is missing. Incoming SMS messages cannot be monitored.',
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
                icon: const Icon(Icons.security, size: 16),
                label: const Text('Grant SIM & SMS Permissions'),
                onPressed: () async {
                  if (!_phoneGranted) await Permission.phone.request();
                  if (!_smsGranted) await Permission.sms.request();
                  await _checkSimPermissions();
                  await _detectSims();
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
              'SIM & SMS Permissions Granted ✓',
              style: TextStyle(
                fontSize: 12,
                color: Colors.green.shade900,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          InkWell(
            onTap: () async {
              await _checkSimPermissions();
              await _detectSims();
            },
            child: Padding(
              padding: const EdgeInsets.all(4.0),
              child: Text(
                'Re-scan',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.green.shade800,
                  fontWeight: FontWeight.bold,
                ),
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
            const Icon(
              Icons.sim_card_alert_outlined,
              size: 72,
              color: Colors.orange,
            ),
            const SizedBox(height: 16),
            const Text(
              'No SIM Cards Detected',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Ensure Phone permission is granted and active SIMs are inserted in the device.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _detectSims,
              icon: const Icon(Icons.refresh),
              label: const Text('Scan Active SIMs'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSimCard(SimInfoModel sim) {
    final subId = sim.subscriptionId;
    final nameCtrl = _nameControllers[subId];
    final numCtrl = _numberControllers[subId];
    final isEnabled = _enabledStates[subId] ?? true;
    final numberSource = _numberSources[subId] ?? 'default';

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
                  backgroundColor: Theme.of(context)
                      .colorScheme
                      .primaryContainer,
                  child: Text(
                    '${sim.slotIndex + 1}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'SIM Slot ${sim.slotIndex + 1}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        'Carrier: ${sim.carrierName} (SubID: ${sim.subscriptionId})',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: isEnabled,
                  onChanged: (val) {
                    setState(() {
                      _enabledStates[subId] = val;
                    });
                  },
                ),
              ],
            ),
            if (sim.detectedNumber.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(
                  'Auto-detected from SIM: ${sim.detectedNumber}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.blueAccent,
                  ),
                ),
              ),
            const Divider(height: 24),
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Custom Label / SIM Name',
                hintText: 'e.g. Personal, Work, Banking SIM',
                prefixIcon: Icon(Icons.label_outline),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: numberSource,
              decoration: const InputDecoration(
                labelText: 'Receiving number source',
                border: OutlineInputBorder(),
              ),
              items: simNumberSourceOptions(sim.slotIndex)
                  .map(
                    (option) => DropdownMenuItem(
                      value: option.$1,
                      child: Text(option.$2),
                    ),
                  )
                  .toList(),
              onChanged: (value) =>
                  setState(() => _numberSources[subId] = value ?? 'default'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: numCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Set Phone Number',
                hintText: 'e.g. +91 98765 43210',
                prefixIcon: Icon(Icons.phone_outlined),
                border: OutlineInputBorder(),
                helperText: 'Set phone number manually to attach to SMS events',
              ),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton.icon(
                onPressed: () => _saveSim(sim),
                icon: const Icon(Icons.save),
                label: const Text('Save SIM Config'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    for (final c in _nameControllers.values) {
      c.dispose();
    }
    for (final c in _numberControllers.values) {
      c.dispose();
    }
    super.dispose();
  }
}

/// Slot-specific labels prevent the two SIM pickers from ever presenting the
/// other slot as an auto-detect option.
List<(String, String)> simNumberSourceOptions(int slotIndex) => [
  ('default', 'Default SIM'),
  (
    'auto_detect',
    'SIM ${slotIndex + 1} (${slotIndex == 0 ? 'Auto detect' : 'Auto Detect'})',
  ),
];
