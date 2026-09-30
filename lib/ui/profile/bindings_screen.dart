import 'package:flutter/material.dart';
import '../../domain/models/user_binding_model.dart';
import '../../domain/models/user_model.dart';
import '../../services/auth_service.dart';

class BindingsScreen extends StatefulWidget {
  const BindingsScreen({super.key});

  @override
  State<BindingsScreen> createState() => _BindingsScreenState();
}

class _BindingsScreenState extends State<BindingsScreen> {
  final AuthService _authService = AuthService.instance;

  UserModel? _user;
  List<UserBindingModel> _bindings = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final user = await _authService.getCurrentUser();
    final bindings = await _authService.getBindings();
    setState(() {
      _user = user;
      _bindings = bindings;
      _isLoading = false;
    });
  }

  Future<void> _showAddBindingDialog() async {
    String type = 'mobile';
    final valueController = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Add Number / Email Binding'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'When an SMS or notification arrives for this number or email, the app associates it with User ID: ${_user?.effectiveUserId ?? 'Guest'}.',
                style: const TextStyle(fontSize: 13, color: Colors.black87),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: type,
                decoration: const InputDecoration(labelText: 'Binding Type', border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: 'mobile', child: Text('Mobile Number')),
                  DropdownMenuItem(value: 'email', child: Text('Email Address')),
                ],
                onChanged: (val) => setDialogState(() => type = val ?? 'mobile'),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: valueController,
                keyboardType: type == 'mobile' ? TextInputType.phone : TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: type == 'mobile' ? 'Mobile Number (e.g. 9876543210)' : 'Email (e.g. user@gmail.com)',
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                final val = valueController.text.trim();
                if (val.isNotEmpty) {
                  await _authService.addBinding(type: type, value: val);
                  Navigator.pop(ctx);
                  _loadData();
                }
              },
              child: const Text('Add Binding'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteBinding(int id) async {
    await _authService.deleteBinding(id);
    _loadData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Number & Email Bindings'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddBindingDialog,
        icon: const Icon(Icons.add_link),
        label: const Text('Add Binding'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildHeaderCard(),
                const SizedBox(height: 16),
                const Text(
                  'Bound Identifiers',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                if (_bindings.isEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Center(
                        child: Column(
                          children: [
                            Icon(Icons.link_off, size: 48, color: Colors.grey.shade400),
                            const SizedBox(height: 8),
                            const Text('No numbers or emails bound yet'),
                            const SizedBox(height: 4),
                            Text(
                              'Add your SIM numbers or emails to automatically tag incoming OTPs with your User ID.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                else
                  ..._bindings.map((b) => _buildBindingTile(b)),
              ],
            ),
    );
  }

  Widget _buildHeaderCard() {
    final user = _user!;
    return Card(
      color: Colors.blue.shade50,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: Colors.blue.shade200,
              child: Icon(user.isGuest ? Icons.person_outline : Icons.account_circle, size: 36, color: Colors.blue.shade900),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.username,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    user.isGuest
                        ? 'Guest User (user_id: null)'
                        : 'User ID: ${user.effectiveUserId} ${user.email.isNotEmpty ? '| ' + user.email : ''}',
                    style: TextStyle(fontSize: 13, color: Colors.blue.shade900),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBindingTile(UserBindingModel b) {
    final isMobile = b.type == 'mobile';
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isMobile ? Colors.green.shade100 : Colors.purple.shade100,
          child: Icon(isMobile ? Icons.phone_android : Icons.email_outlined,
              color: isMobile ? Colors.green.shade800 : Colors.purple.shade800),
        ),
        title: Text(
          b.value,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          'Bound to User ID: ${b.userId} (${isMobile ? 'Mobile' : 'Email'})',
          style: const TextStyle(fontSize: 12),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline, color: Colors.red),
          onPressed: b.id != null ? () => _deleteBinding(b.id!) : null,
        ),
      ),
    );
  }
}
