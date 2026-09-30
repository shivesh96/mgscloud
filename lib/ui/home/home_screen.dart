import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/local/dao/email_dao.dart';
import '../../data/local/dao/event_dao.dart';
import '../../data/local/dao/settings_dao.dart';
import '../../domain/models/event_model.dart';
import '../shared/event_detail_sheet.dart';
import '../../domain/models/sim_info_model.dart';
import '../../domain/models/whatsapp_config_model.dart';
import '../../domain/models/email_config_model.dart';
import '../../services/background_service_manager.dart';
import '../../services/email_reader_service.dart';
import '../../services/event_coordinator.dart';
import '../../services/sim_service.dart';
import '../../services/transport_manager.dart';
import '../../services/whatsapp_service.dart';
import '../auth/auth_screen.dart';
import '../config/config_screen.dart';
import '../config/email_config_screen.dart';
import '../config/otp_rules_screen.dart';
import '../config/sim_config_screen.dart';
import '../config/whatsapp_config_screen.dart';
import '../logs/logs_screen.dart';
import '../permissions/permissions_screen.dart';
import '../profile/bindings_screen.dart';
import '../../domain/models/user_model.dart';
import '../../services/auth_service.dart';
import '../../services/permission_gate_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final EventDao _eventDao = EventDao();
  final SettingsDao _settingsDao = SettingsDao();
  final SimService _simService = SimService();
  final WhatsAppService _whatsAppService = WhatsAppService();
  final EmailReaderService _emailReader = EmailReaderService.instance;
  final EmailDao _emailDao = EmailDao();
  final EventCoordinator _eventCoordinator = EventCoordinator.instance;
  final TransportManager _transportManager = TransportManager.instance;
  final AuthService _authService = AuthService.instance;

  bool _serviceEnabled = true;
  String _protocol = 'HTTP';
  int _todayCount = 0;
  int _pendingCount = 0;

  UserModel? _currentUser;
  List<SimInfoModel> _sims = [];
  List<WhatsAppConfigModel> _whatsAppInstances = [];
  EmailConfigModel? _emailConfig;
  List<EventModel> _liveEvents = [];

  StreamSubscription<EventModel>? _eventSub;
  StreamSubscription<UserModel>? _permSub;
  bool _sendFilteredOnly = true;
  bool _checkingPermissions = true;
  bool _mandatoryPermissionsGranted = false;

  @override
  void initState() {
    super.initState();
    _requestMandatoryPermissions();
    _loadDashboardData();

    // Listen to real-time events processed by EventCoordinator
    _eventSub = _eventCoordinator.onEventProcessed.listen((event) {
      if (mounted) {
        setState(() {
          _liveEvents.insert(0, event);
          if (_liveEvents.length > 10) {
            _liveEvents = _liveEvents.sublist(0, 10);
          }
          _todayCount++;
        });
        _refreshCounters();
      }
    });

    // Listen to dynamic user permission / block status updates from server
    _permSub = _authService.onUserPermissionsChanged.listen((user) {
      if (mounted) {
        setState(() => _currentUser = user);
        if (user.isBlocked) {
          _showPermissionDenied(
            'Your account or device has been blocked by an administrator.',
          );
        }
        if (_mandatoryPermissionsGranted &&
            !user.isGuest &&
            user.authToken.isNotEmpty &&
            !user.isBlocked) {
          EventCoordinator.instance.activateAuthenticatedSession();
          BackgroundServiceManager.instance.startService();
        } else {
          BackgroundServiceManager.instance.stopService();
        }
      }
    });
  }

  Future<void> _requestMandatoryPermissions() async {
    final granted = await PermissionGateService.instance
        .requestMandatoryPermissions();
    if (!mounted) return;
    setState(() {
      _mandatoryPermissionsGranted = granted;
      _checkingPermissions = false;
    });
    if (granted) {
      final settings = await _settingsDao.getSettings();
      if ((settings['server_url'] as String? ?? '').trim().isEmpty && mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const ConfigScreen(requiredSetup: true),
          ),
        );
      }
      await _loadDashboardData();
    }
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    _permSub?.cancel();
    super.dispose();
  }

  Future<void> _loadDashboardData() async {
    final settings = await _settingsDao.getSettings();
    final isEnabled = await _settingsDao.isServiceEnabled();
    final isFiltered = await _settingsDao.isSendFilteredOnly();
    final today = await _eventDao.getTodayEventCount();
    final pending = await _eventDao.getPendingEventCount();
    final events = await _eventDao.getRecentEvents(limit: 10);
    final sims = await _simService.getAllSims();
    final wa = await _whatsAppService.getAllInstances();
    final email = await _emailDao.getEmailConfig();
    final user = await _authService.getCurrentUser();

    if (mounted) {
      setState(() {
        _serviceEnabled = isEnabled;
        _sendFilteredOnly = isFiltered;
        _protocol = settings['protocol'] as String? ?? 'HTTP';
        _todayCount = today;
        _pendingCount = pending;
        _liveEvents = events;
        _sims = sims;
        _whatsAppInstances = wa;
        _emailConfig = email;
        _currentUser = user;
      });
    }

    if (_mandatoryPermissionsGranted &&
        isEnabled &&
        !user.isGuest &&
        user.authToken.isNotEmpty &&
        !user.isBlocked) {
      BackgroundServiceManager.instance.startService();
    }
  }

  void _showPermissionDenied(String reason) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.lock_outline, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text('Permission Denied: $reason')),
          ],
        ),
        backgroundColor: Colors.red.shade700,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<void> _refreshCounters() async {
    final today = await _eventDao.getTodayEventCount();
    final pending = await _eventDao.getPendingEventCount();
    if (mounted) {
      setState(() {
        _todayCount = today;
        _pendingCount = pending;
      });
    }
  }

  Future<void> _toggleService(bool value) async {
    if (!(_currentUser?.canControlService ?? false)) {
      _showPermissionDenied(
        'You need "control_service" permission to start or stop the monitoring service.',
      );
      return;
    }

    await _settingsDao.setServiceEnabled(value);
    setState(() => _serviceEnabled = value);
    if (value) {
      await BackgroundServiceManager.instance.startService();
    } else {
      await BackgroundServiceManager.instance.stopService();
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            value
                ? 'Monitoring service is ACTIVE'
                : 'Monitoring service is PAUSED',
          ),
          backgroundColor: value ? Colors.green : Colors.orange,
        ),
      );
    }
  }

  Future<void> _toggleForwardingMode() async {
    final canToggle =
        _currentUser == null ||
        _currentUser!.isGuest ||
        _currentUser!.canManageSettings;
    if (!canToggle) {
      _showPermissionDenied(
        'You need "manage_settings" permission to change message forwarding mode.',
      );
      return;
    }

    final newMode = !_sendFilteredOnly;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          newMode ? 'Switch to Filtered Messages?' : 'Switch to All Messages?',
        ),
        content: Text(
          newMode
              ? 'Only messages matching configured OTP rules will be transmitted to the server.'
              : 'ALL incoming SMS, WhatsApp, and notification events will be transmitted to the server.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: newMode
                  ? Colors.amber.shade700
                  : Colors.blue.shade700,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Confirm Switch',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _authService.setForwardingMode(newMode ? 'filtered' : 'all');
      setState(() => _sendFilteredOnly = newMode);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Message Sending Mode updated to: ${newMode ? "Filtered (OTP Only)" : "All Messages"}',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  Future<void> _syncPendingNow() async {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Retrying pending events...')));
    final count = await _transportManager.syncPendingEvents();
    await _loadDashboardData();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Successfully transmitted $count pending event(s)!'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _syncEmailsNow() async {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Checking IMAP emails...')));
    final res = await _emailReader.syncEmailsNow();
    await _loadDashboardData();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res['message'] as String? ?? ''),
          backgroundColor: res['success'] == true ? Colors.green : Colors.red,
        ),
      );
    }
  }

  void _showTestEventDialog() {
    final senderCtrl = TextEditingController(text: 'MOBIK');
    final scCtrl = TextEditingController(text: '+917012075009');
    final messageCtrl = TextEditingController(
      text: '819413 is the OTP to complete your MobiKwik wallet login.',
    );
    String source = 'sms';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Simulate Incoming Event'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: source,
                  decoration: const InputDecoration(labelText: 'Source'),
                  items: const [
                    DropdownMenuItem(value: 'sms', child: Text('SMS Message')),
                    DropdownMenuItem(
                      value: 'whatsapp',
                      child: Text('WhatsApp Notification'),
                    ),
                    DropdownMenuItem(
                      value: 'email',
                      child: Text('Email Message'),
                    ),
                  ],
                  onChanged: (val) =>
                      setDialogState(() => source = val ?? 'sms'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: senderCtrl,
                  decoration: InputDecoration(
                    labelText: source == 'email'
                        ? 'From Email'
                        : 'Sender / Contact',
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: scCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Service Center (Optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: messageCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Message Body',
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
                Navigator.pop(ctx);
                try {
                  final res = await _eventCoordinator.sendTestEvent(
                    source: source,
                    sender: senderCtrl.text.trim(),
                    serviceCenter: scCtrl.text.trim(),
                    message: messageCtrl.text.trim(),
                    simSlot: 0,
                    packageName: source == 'whatsapp' ? 'com.whatsapp' : null,
                  );
                  await _loadDashboardData();
                  if (mounted) {
                    if (res != null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Simulated event captured! OTP: ${res.otp ?? "None"} | Status: ${res.deliveryStatus}',
                          ),
                          backgroundColor: Colors.green,
                        ),
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Event dropped (check service status/settings).',
                          ),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Error simulating event: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
              child: const Text('Send Event'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingPermissions || !_mandatoryPermissionsGranted) {
      return Scaffold(
        appBar: AppBar(title: const Text('MSG to Server')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: _checkingPermissions
                ? const CircularProgressIndicator()
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.security,
                        size: 56,
                        color: Colors.orange,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'SMS, Phone, Notifications, and battery-unrestricted access are required before monitoring can start.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _requestMandatoryPermissions,
                        child: const Text('Grant required permissions'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const PermissionsScreen(),
                          ),
                        ).then((_) => _requestMandatoryPermissions()),
                        child: const Text('Open permission settings'),
                      ),
                    ],
                  ),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'MSG to Server',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Dashboard',
            onPressed: _loadDashboardData,
          ),
          IconButton(
            icon: const Icon(Icons.flash_on),
            tooltip: 'Send Test Event',
            onPressed: _showTestEventDialog,
          ),
          PopupMenuButton<String>(
            onSelected: (route) {
              if (route == 'auth') {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AuthScreen()),
                ).then((_) => _loadDashboardData());
              } else if (route == 'bindings') {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const BindingsScreen()),
                ).then((_) => _loadDashboardData());
              } else if (route == 'otp_rules') {
                if (!(_currentUser?.canViewRules ?? false)) {
                  _showPermissionDenied(
                    'You need "view_rules" or "manage_rules" permission to access OTP rules.',
                  );
                  return;
                }
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const OtpRulesScreen()),
                ).then((_) => _loadDashboardData());
              } else if (route == 'server') {
                if (!(_currentUser?.canManageSettings ?? false)) {
                  _showPermissionDenied(
                    'You need "manage_settings" permission to access server configuration.',
                  );
                  return;
                }
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ConfigScreen()),
                ).then((_) => _loadDashboardData());
              } else if (route == 'sim') {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SimConfigScreen()),
                ).then((_) => _loadDashboardData());
              } else if (route == 'whatsapp') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const WhatsAppConfigScreen(),
                  ),
                ).then((_) => _loadDashboardData());
              } else if (route == 'email') {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const EmailConfigScreen()),
                ).then((_) => _loadDashboardData());
              } else if (route == 'permissions') {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const PermissionsScreen()),
                ).then((_) => _loadDashboardData());
              } else if (route == 'logs') {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const LogsScreen()),
                ).then((_) => _loadDashboardData());
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'auth',
                child: ListTile(
                  leading: Icon(Icons.account_circle),
                  title: Text('Account & Login'),
                ),
              ),
              const PopupMenuItem(
                value: 'bindings',
                child: ListTile(
                  leading: Icon(Icons.link),
                  title: Text('Number / Email Bindings'),
                ),
              ),
              const PopupMenuItem(
                value: 'otp_rules',
                child: ListTile(
                  leading: Icon(Icons.rule),
                  title: Text('OTP Parsing Rules'),
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'server',
                child: ListTile(
                  leading: Icon(Icons.dns),
                  title: Text('Server Settings'),
                ),
              ),
              const PopupMenuItem(
                value: 'sim',
                child: ListTile(
                  leading: Icon(Icons.sim_card),
                  title: Text('SIM Cards'),
                ),
              ),
              const PopupMenuItem(
                value: 'whatsapp',
                child: ListTile(
                  leading: Icon(Icons.chat),
                  title: Text('WhatsApp & Clones'),
                ),
              ),
              const PopupMenuItem(
                value: 'email',
                child: ListTile(
                  leading: Icon(Icons.email),
                  title: Text('Email Reader'),
                ),
              ),
              const PopupMenuItem(
                value: 'permissions',
                child: ListTile(
                  leading: Icon(Icons.security),
                  title: Text('Permissions'),
                ),
              ),
              const PopupMenuItem(
                value: 'logs',
                child: ListTile(
                  leading: Icon(Icons.history),
                  title: Text('Event Logs'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadDashboardData,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildUserAccountBanner(),
            const SizedBox(height: 12),
            _buildForwardingModeBanner(),
            const SizedBox(height: 12),
            _buildServiceStatusCard(),
            const SizedBox(height: 16),
            _buildOverviewRow(),
            const SizedBox(height: 16),
            _buildSectionHeader('Live Events Stream (Latest 10)'),
            const SizedBox(height: 8),
            _buildLiveEventsList(),
          ],
        ),
      ),
    );
  }

  Widget _buildForwardingModeBanner() {
    final isFiltered = _sendFilteredOnly;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isFiltered ? Colors.amber.shade50 : Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isFiltered ? Colors.amber.shade300 : Colors.blue.shade200,
        ),
      ),
      child: Row(
        children: [
          Icon(
            isFiltered ? Icons.filter_alt : Icons.all_inclusive,
            color: isFiltered ? Colors.amber.shade800 : Colors.blue.shade800,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isFiltered
                      ? 'Mode: Filtered Messages (OTP Only)'
                      : 'Mode: All Messages',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: isFiltered
                        ? Colors.amber.shade900
                        : Colors.blue.shade900,
                  ),
                ),
                Text(
                  isFiltered
                      ? 'Only events matching active OTP rules are forwarded'
                      : 'All incoming SMS and notifications are forwarded',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                ),
              ],
            ),
          ),
          TextButton(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              backgroundColor: isFiltered
                  ? Colors.amber.shade200
                  : Colors.blue.shade200,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: _toggleForwardingMode,
            child: Text(
              'Switch',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
                color: isFiltered
                    ? Colors.amber.shade900
                    : Colors.blue.shade900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserAccountBanner() {
    final user = _currentUser;
    final isGuest = user == null || user.isGuest;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isGuest ? Colors.amber.shade50 : Colors.indigo.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isGuest ? Colors.amber.shade300 : Colors.indigo.shade200,
        ),
      ),
      child: Row(
        children: [
          Icon(
            isGuest ? Icons.person_outline : Icons.verified_user,
            color: isGuest ? Colors.amber.shade800 : Colors.indigo.shade800,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isGuest
                      ? 'Guest Mode (user_id = null)'
                      : 'User: ${user.username} (ID: ${user.effectiveUserId})',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: isGuest
                        ? Colors.amber.shade900
                        : Colors.indigo.shade900,
                  ),
                ),
                Text(
                  isGuest
                      ? 'Tap to login with Mobile/Email & bind numbers'
                      : 'Bound: ${user.mobile.isNotEmpty ? user.mobile : user.email}',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AuthScreen()),
              ).then((_) => _loadDashboardData());
            },
            child: Text(isGuest ? 'Login' : 'Switch'),
          ),
        ],
      ),
    );
  }

  Widget _buildServiceStatusCard() {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              children: [
                Icon(
                  Icons.circle,
                  color: _serviceEnabled ? Colors.green : Colors.red,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Text(
                  _serviceEnabled ? 'SERVICE ACTIVE' : 'SERVICE PAUSED',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.1,
                    color: _serviceEnabled
                        ? Colors.green.shade800
                        : Colors.red.shade800,
                  ),
                ),
                const Spacer(),
                Switch(
                  value: _serviceEnabled,
                  activeColor: Colors.green,
                  onChanged: _toggleService,
                ),
              ],
            ),
            const Divider(height: 16),
            Row(
              children: [
                const Icon(Icons.cloud_outlined, size: 20, color: Colors.grey),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _currentUser != null && !_currentUser!.isGuest
                            ? 'Connected securely'
                            : 'Login required',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'Protocol: $_protocol',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit, size: 18),
                  tooltip: 'Edit Server',
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ConfigScreen()),
                    ).then((_) => _loadDashboardData());
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Today\'s Events',
                          style: TextStyle(
                            color: Colors.blue.shade700,
                            fontSize: 12,
                          ),
                        ),
                        Text(
                          '$_todayCount',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue.shade900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InkWell(
                    onTap: _pendingCount > 0 ? _syncPendingNow : null,
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _pendingCount > 0
                            ? Colors.orange.shade50
                            : Colors.green.shade50,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'Pending Sync',
                                style: TextStyle(
                                  color: _pendingCount > 0
                                      ? Colors.orange.shade900
                                      : Colors.green.shade900,
                                  fontSize: 12,
                                ),
                              ),
                              if (_pendingCount > 0) ...[
                                const Spacer(),
                                const Icon(
                                  Icons.sync,
                                  size: 14,
                                  color: Colors.orange,
                                ),
                              ],
                            ],
                          ),
                          Text(
                            '$_pendingCount',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: _pendingCount > 0
                                  ? Colors.orange.shade900
                                  : Colors.green.shade900,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverviewRow() {
    return Column(
      children: [
        // SIM Card Overview Card
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.deepPurple.shade100,
              child: const Icon(Icons.sim_card, color: Colors.deepPurple),
            ),
            title: Text(
              'SIM Cards (${_sims.length} Active)',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              _sims.isEmpty
                  ? 'No SIMs detected. Tap to scan & configure.'
                  : _sims
                        .map((s) => '${s.effectiveName}: ${s.effectiveNumber}')
                        .join(' | '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SimConfigScreen()),
              ).then((_) => _loadDashboardData());
            },
          ),
        ),
        const SizedBox(height: 8),
        // WhatsApp & Clones Card
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.green.shade100,
              child: const Icon(Icons.chat, color: Colors.green),
            ),
            title: Text(
              'WhatsApp & Clones (${_whatsAppInstances.length} Configured)',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              _whatsAppInstances.isEmpty
                  ? 'Tap to scan WhatsApp, Business & Dual Apps.'
                  : _whatsAppInstances
                        .map(
                          (w) =>
                              '${w.instanceName}: ${w.phoneNumber.isNotEmpty ? w.phoneNumber : "No number"}',
                        )
                        .join(' | '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const WhatsAppConfigScreen()),
              ).then((_) => _loadDashboardData());
            },
          ),
        ),
        const SizedBox(height: 8),
        // Email Reader Card
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.blue.shade100,
              child: const Icon(Icons.email, color: Colors.blueAccent),
            ),
            title: const Text(
              'Email Reader (IMAP)',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              _emailConfig != null && _emailConfig!.enabled
                  ? 'Active: ${_emailConfig!.emailAddress.isNotEmpty ? _emailConfig!.emailAddress : _emailConfig!.imapHost}'
                  : 'Disabled. Tap to configure IMAP email credentials.',
              style: const TextStyle(fontSize: 12),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_emailConfig != null && _emailConfig!.enabled)
                  IconButton(
                    icon: const Icon(Icons.sync, color: Colors.blueAccent),
                    tooltip: 'Sync Emails Now',
                    onPressed: _syncEmailsNow,
                  ),
                const Icon(Icons.chevron_right),
              ],
            ),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const EmailConfigScreen()),
              ).then((_) => _loadDashboardData());
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        TextButton(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const LogsScreen()),
            ).then((_) => _loadDashboardData());
          },
          child: const Text('View All Logs'),
        ),
      ],
    );
  }

  Widget _buildLiveEventsList() {
    if (_liveEvents.isEmpty) {
      return Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: const Padding(
          padding: EdgeInsets.all(32.0),
          child: Center(
            child: Column(
              children: [
                Icon(Icons.inbox_outlined, size: 48, color: Colors.grey),
                SizedBox(height: 8),
                Text(
                  'No events captured yet.',
                  style: TextStyle(color: Colors.grey),
                ),
                SizedBox(height: 4),
                Text(
                  'Incoming SMS, WhatsApp notifications & emails will appear here live.',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      children: _liveEvents.map((event) => _buildLiveEventItem(event)).toList(),
    );
  }

  Widget _buildLiveEventItem(EventModel event) {
    Color badgeColor;
    IconData icon;
    switch (event.source.toLowerCase()) {
      case 'sms':
        badgeColor = Colors.blue;
        icon = Icons.sms;
        break;
      case 'whatsapp':
        badgeColor = Colors.green;
        icon = Icons.chat;
        break;
      case 'email':
        badgeColor = Colors.deepPurple;
        icon = Icons.email;
        break;
      default:
        badgeColor = Colors.teal;
        icon = Icons.notifications;
    }

    Color statusColor;
    switch (event.deliveryStatus.toLowerCase()) {
      case 'sent':
        statusColor = Colors.green;
        break;
      case 'failed':
        statusColor = Colors.red;
        break;
      default:
        statusColor = Colors.orange;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        onTap: () => showEventDetailSheet(context, event),
        leading: CircleAvatar(
          backgroundColor: badgeColor.withValues(alpha: 0.12),
          child: Icon(icon, color: badgeColor, size: 20),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                event.sender ?? event.title ?? 'Unknown',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                event.deliveryStatus.toUpperCase(),
                style: TextStyle(
                  color: statusColor,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              event.message ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
            if (event.otp != null && event.otp!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.amber.shade100,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.amber.shade400),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.key, size: 14, color: Colors.amber.shade900),
                    const SizedBox(width: 4),
                    Text(
                      'OTP: ${event.otp}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: Colors.amber.shade900,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              children: [
                if (event.userId != null)
                  Text(
                    'UID: ${event.userId} • ',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.indigo.shade700,
                    ),
                  ),
                if (event.simName != null || event.simSlot != null)
                  Text(
                    '${event.simName ?? "SIM ${event.simSlot! + 1}"} • ',
                    style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                  ),
                if (event.instanceName != null)
                  Text(
                    '${event.instanceName} • ',
                    style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                  ),
                if (event.serviceCenter != null &&
                    event.serviceCenter!.isNotEmpty)
                  Text(
                    'SC: ${event.serviceCenter} • ',
                    style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                  ),
                Text(
                  event.timestamp.split('T').last.split('.').first,
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
