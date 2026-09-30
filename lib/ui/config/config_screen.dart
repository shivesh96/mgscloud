import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/local/dao/settings_dao.dart';
import '../../domain/models/user_model.dart';
import '../../services/auth_service.dart';
import '../../services/transport_manager.dart';
import '../auth/auth_screen.dart';

class ConfigScreen extends StatefulWidget {
  const ConfigScreen({super.key, this.requiredSetup = false});
  final bool requiredSetup;

  @override
  State<ConfigScreen> createState() => _ConfigScreenState();
}

class _ConfigScreenState extends State<ConfigScreen> {
  final _formKey = GlobalKey<FormState>();
  final _settingsDao = SettingsDao();
  final _transportManager = TransportManager.instance;
  final _authService = AuthService.instance;

  final _urlController = TextEditingController();
  final _tokenController = TextEditingController();
  final _timeoutController = TextEditingController(text: '30');
  final _retryCountController = TextEditingController(text: '3');

  String _protocol = 'HTTP';
  String _method = 'POST';
  String _authType = 'NONE';
  String _forwardingMode = 'filtered';

  UserModel? _currentUser;
  StreamSubscription<UserModel>? _permSub;

  bool _isTesting = false;
  String? _testMessage;
  bool? _testSuccess;

  @override
  void initState() {
    super.initState();
    _loadUser();
    _loadSettings();

    _permSub = _authService.onUserPermissionsChanged.listen((user) {
      if (!mounted) return;
      setState(() => _currentUser = user);
    });
  }

  Future<void> _loadUser() async {
    final user = await _authService.getCurrentUser();
    if (mounted) {
      setState(() => _currentUser = user);
    }
  }

  Future<void> _loadSettings() async {
    final settings = await _settingsDao.getSettings();
    final mode = await _authService.getForwardingMode();
    if (mounted) {
      setState(() {
        _urlController.text =
            settings['server_url'] as String? ??
            'https://example.com/api/v1/events';
        _protocol = settings['protocol'] as String? ?? 'HTTP';
        _method = settings['http_method'] as String? ?? 'POST';
        _authType = settings['auth_type'] as String? ?? 'NONE';
        _tokenController.text = settings['auth_token'] as String? ?? '';
        _timeoutController.text = (settings['connection_timeout'] as int? ?? 30)
            .toString();
        _retryCountController.text = (settings['retry_count'] as int? ?? 3)
            .toString();
        _forwardingMode = mode;
      });
    }
  }

  Future<void> _toggleForwardingMode(bool sendAll) async {
    final canToggle =
        _currentUser == null ||
        _currentUser!.isGuest ||
        _currentUser!.canManageSettings;
    if (!canToggle) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Permission Denied: You do not have permission to change settings (manage_settings required).',
          ),
          backgroundColor: Colors.red.shade700,
        ),
      );
      return;
    }

    final targetMode = sendAll ? 'all' : 'filtered';
    final targetTitle = sendAll
        ? 'Switch to All Messages'
        : 'Switch to Filtered Messages';
    final targetDesc = sendAll
        ? 'All incoming messages (SMS, WhatsApp, and email) will be forwarded to the server, including personal or non-OTP traffic. Are you sure?'
        : 'Only messages matching configured OTP extraction rules will be forwarded to the server. Non-OTP messages will be ignored. Are you sure?';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(targetTitle),
        content: Text(targetDesc),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm Switch'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _authService.setForwardingMode(targetMode);
      setState(() => _forwardingMode = targetMode);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Message sending mode updated to: ${sendAll ? "All Messages" : "Filtered Messages"}',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  Future<void> _saveSettings() async {
    if (_formKey.currentState!.validate()) {
      final timeout = int.tryParse(_timeoutController.text.trim()) ?? 30;
      final retries = int.tryParse(_retryCountController.text.trim()) ?? 3;

      await _settingsDao.updateSettings({
        'server_url': _urlController.text.trim(),
        'protocol': _protocol,
        'http_method': _method,
        'auth_type': _authType,
        'auth_token': _tokenController.text.trim(),
        'connection_timeout': timeout,
        'retry_count': retries,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Server settings saved successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  Future<void> _testServer() async {
    if (_urlController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a server URL first')),
      );
      return;
    }

    setState(() {
      _isTesting = true;
      _testMessage = null;
      _testSuccess = null;
    });

    final res = await _transportManager.testConnection(
      serverUrl: _urlController.text.trim(),
      protocol: _protocol,
      method: _method,
      authType: _authType,
      authToken: _tokenController.text.trim(),
    );

    setState(() {
      _isTesting = false;
      _testSuccess = res['success'] as bool? ?? false;
      _testMessage = res['message'] as String? ?? '';
    });
    if (res['success'] == true) {
      await _saveSettings();
      if (mounted && widget.requiredSetup) {
        await Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const AuthScreen()),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !widget.requiredSetup,
      child: Scaffold(
        appBar: AppBar(title: const Text('Server Configuration')),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Message Sending Mode',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: _forwardingMode == 'filtered'
                                  ? Colors.blue.shade50
                                  : Colors.purple.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: _forwardingMode == 'filtered'
                                    ? Colors.blue
                                    : Colors.purple,
                              ),
                            ),
                            child: Text(
                              _forwardingMode == 'filtered'
                                  ? 'FILTERED (OTP ONLY)'
                                  : 'ALL MESSAGES',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: _forwardingMode == 'filtered'
                                    ? Colors.blue.shade800
                                    : Colors.purple.shade800,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _forwardingMode == 'filtered'
                            ? 'Only incoming messages matching configured OTP extraction rules are forwarded to the server.'
                            : 'ALL incoming SMS, WhatsApp, and email messages are forwarded to the server immediately.',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      const SizedBox(height: 12),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'Forward All Messages',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: const Text(
                          'Disable rule filtering and capture full message stream',
                        ),
                        value: _forwardingMode == 'all',
                        onChanged: (val) => _toggleForwardingMode(val),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Endpoint & Protocol',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _urlController,
                        decoration: const InputDecoration(
                          labelText: 'Server URL',
                          hintText: 'https://your-server.com/api/v1/events',
                          prefixIcon: Icon(Icons.cloud_upload_outlined),
                          border: OutlineInputBorder(),
                        ),
                        validator: (val) => val == null || val.trim().isEmpty
                            ? 'Server URL is required'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: _protocol,
                        decoration: const InputDecoration(
                          labelText: 'Communication Protocol',
                          prefixIcon: Icon(Icons.swap_calls),
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'HTTP',
                            child: Text('HTTP / HTTPS (REST)'),
                          ),
                          DropdownMenuItem(
                            value: 'WebSocket',
                            child: Text('WebSocket / WSS (Live Stream)'),
                          ),
                        ],
                        onChanged: (val) => setState(() => _protocol = val!),
                      ),
                      if (_protocol == 'HTTP') ...[
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          value: _method,
                          decoration: const InputDecoration(
                            labelText: 'HTTP Method',
                            prefixIcon: Icon(Icons.http),
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'POST',
                              child: Text(
                                'POST (Recommended for sensitive data)',
                              ),
                            ),
                            DropdownMenuItem(value: 'GET', child: Text('GET')),
                          ],
                          onChanged: (val) => setState(() => _method = val!),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Authentication',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: _authType,
                        decoration: const InputDecoration(
                          labelText: 'Auth Mechanism',
                          prefixIcon: Icon(Icons.key_outlined),
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'NONE',
                            child: Text('None (Public endpoint)'),
                          ),
                          DropdownMenuItem(
                            value: 'BASIC',
                            child: Text('Basic Auth (username:password)'),
                          ),
                          DropdownMenuItem(
                            value: 'API_KEY',
                            child: Text('API Key (X-Api-Key Header)'),
                          ),
                          DropdownMenuItem(
                            value: 'BEARER',
                            child: Text('Bearer Token (Authorization Header)'),
                          ),
                        ],
                        onChanged: (val) => setState(() => _authType = val!),
                      ),
                      if (_authType != 'NONE') ...[
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _tokenController,
                          decoration: InputDecoration(
                            labelText: _authType == 'API_KEY'
                                ? 'API Key Value'
                                : (_authType == 'BASIC'
                                      ? 'username:password'
                                      : 'Bearer Token Value'),
                            hintText: _authType == 'BASIC'
                                ? 'e.g. admin:admin123'
                                : 'Enter secret token or key',
                            prefixIcon: const Icon(Icons.lock_outline),
                            border: const OutlineInputBorder(),
                          ),
                          validator: (val) => val == null || val.trim().isEmpty
                              ? 'Credential cannot be empty'
                              : null,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Connection Reliability',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _timeoutController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Timeout (sec)',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _retryCountController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Max Retries',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (_testMessage != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _testSuccess == true
                        ? Colors.green.shade50
                        : Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _testSuccess == true ? Colors.green : Colors.red,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _testSuccess == true ? Icons.check_circle : Icons.error,
                        color: _testSuccess == true ? Colors.green : Colors.red,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _testMessage!,
                          style: TextStyle(
                            color: _testSuccess == true
                                ? Colors.green.shade900
                                : Colors.red.shade900,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isTesting ? null : _testServer,
                      icon: _isTesting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.wifi_tethering),
                      label: const Text('Test Connection'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _saveSettings,
                      icon: const Icon(Icons.save),
                      label: const Text('Save Server Settings'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _permSub?.cancel();
    _urlController.dispose();
    _tokenController.dispose();
    _timeoutController.dispose();
    _retryCountController.dispose();
    super.dispose();
  }
}
