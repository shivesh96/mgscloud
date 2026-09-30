import 'package:flutter/material.dart';
import '../../domain/models/user_model.dart';
import '../../services/auth_service.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final AuthService _authService = AuthService.instance;

  // Login controllers
  final _loginIdController = TextEditingController();
  final _loginPasswordController = TextEditingController();

  bool _isLoading = false;
  bool _isValidating = false;
  UserModel? _currentUser;

  @override
  void initState() {
    super.initState();
    _loadCurrentUser();
  }

  Future<void> _loadCurrentUser() async {
    setState(() => _isLoading = true);
    final user = await _authService.getCurrentUser();
    if (mounted) {
      setState(() {
        _currentUser = user;
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _loginIdController.dispose();
    _loginPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    final id = _loginIdController.text.trim();
    final pass = _loginPasswordController.text.trim();

    if (id.isEmpty) {
      _showSnack('Please enter your Username, Mobile number or Email', isError: true);
      return;
    }
    if (pass.isEmpty) {
      _showSnack('Please enter your password', isError: true);
      return;
    }

    setState(() => _isLoading = true);
    final res = await _authService.login(identifier: id, password: pass);
    final user = await _authService.getCurrentUser();
    setState(() {
      _isLoading = false;
      _currentUser = user;
    });

    if (mounted) {
      _showSnack(
        res['message'] as String? ?? (res['success'] == true ? 'Login successful' : 'Login failed'),
        isError: res['success'] != true,
      );
    }
  }

  Future<void> _handleValidate() async {
    setState(() => _isValidating = true);
    final res = await _authService.validateAndRefreshUser();
    final user = await _authService.getCurrentUser();
    setState(() {
      _isValidating = false;
      _currentUser = user;
    });

    if (mounted) {
      _showSnack(
        res['message'] as String? ?? 'Validation completed',
        isError: res['success'] != true,
      );
    }
  }

  Future<void> _handleLogout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Logout'),
        content: const Text('Are you sure you want to log out of this account?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Log Out'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);
    await _authService.logout();
    final user = await _authService.getCurrentUser();
    setState(() {
      _isLoading = false;
      _currentUser = user;
      _loginPasswordController.clear();
    });

    if (mounted) {
      _showSnack('You have logged out.');
    }
  }

  Future<void> _handleGuest() async {
    setState(() => _isLoading = true);
    await _authService.continueAsGuest();
    final user = await _authService.getCurrentUser();
    setState(() {
      _isLoading = false;
      _currentUser = user;
    });

    if (mounted) {
      _showSnack('Operating in Guest Mode (user_id = null)');
      Navigator.pop(context, true);
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = _currentUser;
    final isLoggedIn = user != null && !user.isGuest;

    return Scaffold(
      appBar: AppBar(
        title: Text(isLoggedIn ? 'User Profile & Validation' : 'Sign In to MSG Server'),
        actions: [
          if (isLoggedIn)
            IconButton(
              icon: _isValidating
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.verified_user_outlined),
              tooltip: 'Validate & Refresh Account',
              onPressed: _isValidating ? null : _handleValidate,
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : isLoggedIn
              ? _buildLoggedInProfile(user)
              : _buildLoginForm(),
    );
  }

  Widget _buildLoggedInProfile(UserModel user) {
    final statusColor = user.status == 'active' ? Colors.green : (user.status == 'blocked' ? Colors.red : Colors.orange);
    final deviceColor = user.deviceStatus == 'active' ? Colors.green : Colors.red;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // User Identity Header Card
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                CircleAvatar(
                  radius: 36,
                  backgroundColor: user.isAdmin ? Colors.deepPurple.shade100 : Colors.blue.shade100,
                  child: Icon(
                    user.isAdmin ? Icons.admin_panel_settings : Icons.person,
                    size: 40,
                    color: user.isAdmin ? Colors.deepPurple : Colors.blue.shade800,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  user.username,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  'User ID #${user.effectiveUserId ?? "N/A"}',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.indigo.shade50,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.indigo.shade200),
                      ),
                      child: Text(
                        'ROLE: ${user.role.toUpperCase()}',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.indigo.shade800),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: statusColor),
                      ),
                      child: Text(
                        'ACCOUNT: ${user.status.toUpperCase()}',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: statusColor),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: deviceColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: deviceColor),
                  ),
                  child: Text(
                    'DEVICE: ${user.deviceStatus.toUpperCase()}',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: deviceColor),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Granted Permissions Card
        Card(
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.shield_outlined, size: 20, color: Colors.indigo),
                    SizedBox(width: 8),
                    Text('Granted Permissions', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  ],
                ),
                const SizedBox(height: 12),
                if (user.permissions.isEmpty)
                  const Text('No permissions assigned to this user.', style: TextStyle(color: Colors.grey, fontSize: 13))
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: user.permissions.map((perm) {
                      return Chip(
                        avatar: Icon(
                          perm.contains('manage') ? Icons.security : Icons.check_circle_outline,
                          size: 16,
                          color: Colors.indigo,
                        ),
                        label: Text(perm, style: const TextStyle(fontSize: 12)),
                        backgroundColor: Colors.indigo.shade50,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      );
                    }).toList(),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Contact & Binding Details
        Card(
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.contact_phone_outlined, size: 20, color: Colors.indigo),
                    SizedBox(width: 8),
                    Text('Contact & Session Details', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  ],
                ),
                const SizedBox(height: 12),
                _buildInfoRow('Mobile Number', user.mobile.isNotEmpty ? user.mobile : 'Not set'),
                const Divider(height: 16),
                _buildInfoRow('Email Address', user.email.isNotEmpty ? user.email : 'Not set'),
                const Divider(height: 16),
                _buildInfoRow('Session Token', user.authToken.isNotEmpty ? '${user.authToken.substring(0, user.authToken.length > 15 ? 15 : user.authToken.length)}...' : 'None'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),

        // Action Buttons
        ElevatedButton.icon(
          onPressed: _isValidating ? null : _handleValidate,
          icon: _isValidating
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.refresh),
          label: const Text('Validate & Refresh Account with Server'),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _handleLogout,
          icon: const Icon(Icons.logout, color: Colors.red),
          label: const Text('Log Out', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: Colors.red),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
        Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildLoginForm() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // Security Notice Banner (Registration disabled notice)
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.blue.shade200),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.admin_panel_settings_outlined, color: Colors.blue.shade800),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Managed Enterprise Security',
                      style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue.shade900),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'User accounts are provisioned and assigned roles by system administrators. In-app registration is disabled. Use the credentials provided by your admin.',
                      style: TextStyle(fontSize: 12, color: Colors.blue.shade800, height: 1.3),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        const Text(
          'Sign In',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        Text(
          'Enter your registered username, mobile number, or email',
          style: TextStyle(color: Colors.grey.shade600),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _loginIdController,
          decoration: const InputDecoration(
            labelText: 'Username, Mobile, or Email',
            hintText: 'e.g. admin or 9876543210 or user@cybolite.com',
            prefixIcon: Icon(Icons.account_circle_outlined),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _loginPasswordController,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Password',
            prefixIcon: Icon(Icons.lock_outline),
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) => _handleLogin(),
        ),
        const SizedBox(height: 24),
        ElevatedButton.icon(
          onPressed: _handleLogin,
          icon: const Icon(Icons.login),
          label: const Text('Sign In'),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 20),
        Center(
          child: TextButton(
            onPressed: _handleGuest,
            child: const Text('Continue in Guest Mode (Read-only / user_id = null)'),
          ),
        ),
      ],
    );
  }
}

