import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/local/dao/email_dao.dart';
import '../../domain/models/email_config_model.dart';
import '../../services/email_reader_service.dart';

class EmailConfigScreen extends StatefulWidget {
  const EmailConfigScreen({super.key});

  @override
  State<EmailConfigScreen> createState() => _EmailConfigScreenState();
}

class _EmailConfigScreenState extends State<EmailConfigScreen> {
  final _dao = EmailDao();
  List<EmailConfigModel> _accounts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final accounts = await _dao.getEmailConfigs();
    if (mounted) {
      setState(() {
        _accounts = accounts;
        _loading = false;
      });
    }
  }

  Future<void> _edit([EmailConfigModel? account]) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => _EmailAccountEditor(account: account)),
    );
    if (saved == true) await _load();
  }

  Future<void> _delete(EmailConfigModel account) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${account.emailAddress}?'),
        content: const Text(
          'This stops its listener and removes its saved IMAP credentials and dedupe history.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _dao.deleteEmailConfig(account.id!);
      await EmailReaderService.instance.refreshListeners();
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Email Accounts (IMAP IDLE)')),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () => _edit(),
      icon: const Icon(Icons.add),
      label: const Text('Add account'),
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _accounts.isEmpty
        ? const Center(
            child: Text(
              'No email accounts configured.\nAdd an account to receive mail in real time.',
              textAlign: TextAlign.center,
            ),
          )
        : ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _accounts.length,
            itemBuilder: (context, index) {
              final account = _accounts[index];
              final lastSync = account.lastSyncedAt == null
                  ? 'Not connected yet'
                  : 'Last activity ${DateFormat('dd MMM, HH:mm').format(DateTime.fromMillisecondsSinceEpoch(account.lastSyncedAt!))}';
              return Card(
                child: ListTile(
                  leading: Icon(
                    account.enabled
                        ? Icons.mark_email_read_outlined
                        : Icons.pause_circle_outline,
                    color: account.enabled ? Colors.green : Colors.grey,
                  ),
                  title: Text(
                    account.emailAddress.isEmpty
                        ? account.username
                        : account.emailAddress,
                  ),
                  subtitle: Text(
                    '${account.imapHost} • ${account.folder}\n${account.enabled ? 'IDLE listener enabled' : 'Paused'} • $lastSync',
                  ),
                  isThreeLine: true,
                  onTap: () => _edit(account),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _delete(account),
                  ),
                ),
              );
            },
          ),
  );
}

class _EmailAccountEditor extends StatefulWidget {
  const _EmailAccountEditor({this.account});
  final EmailConfigModel? account;
  @override
  State<_EmailAccountEditor> createState() => _EmailAccountEditorState();
}

class _EmailAccountEditorState extends State<_EmailAccountEditor> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _email = TextEditingController(
    text: widget.account?.emailAddress ?? '',
  );
  late final TextEditingController _host = TextEditingController(
    text: widget.account?.imapHost ?? 'imap.gmail.com',
  );
  late final TextEditingController _port = TextEditingController(
    text: '${widget.account?.imapPort ?? 993}',
  );
  late final TextEditingController _username = TextEditingController(
    text: widget.account?.username ?? '',
  );
  late final TextEditingController _password = TextEditingController(
    text: widget.account?.password ?? '',
  );
  late final TextEditingController _folder = TextEditingController(
    text: widget.account?.folder ?? 'INBOX',
  );
  late bool _ssl = widget.account?.useSsl ?? true;
  late bool _enabled = widget.account?.enabled ?? true;
  bool _busy = false;

  EmailConfigModel _model() => EmailConfigModel(
    id: widget.account?.id,
    emailAddress: _email.text.trim(),
    imapHost: _host.text.trim(),
    imapPort: int.tryParse(_port.text) ?? 993,
    useSsl: _ssl,
    username: _username.text.trim().isEmpty
        ? _email.text.trim()
        : _username.text.trim(),
    password: _password.text.trim(),
    folder: _folder.text.trim().isEmpty ? 'INBOX' : _folder.text.trim(),
    lastSyncedAt: widget.account?.lastSyncedAt,
    enabled: _enabled,
    updatedAt: DateTime.now().millisecondsSinceEpoch,
  );

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    await EmailDao().saveEmailConfig(_model());
    await EmailReaderService.instance.refreshListeners();
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _test() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final result = await EmailReaderService.instance.testConnection(_model());
    if (mounted) {
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message'] as String),
          backgroundColor: result['success'] == true
              ? Colors.green
              : Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.account == null ? 'Add email account' : 'Edit email account',
      ),
    ),
    body: Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SwitchListTile(
            title: const Text('Enable real-time IMAP IDLE'),
            subtitle: const Text('Keeps this account connected independently.'),
            value: _enabled,
            onChanged: (v) => setState(() => _enabled = v),
          ),
          _field(_email, 'Email address', type: TextInputType.emailAddress),
          _field(_host, 'IMAP host'),
          Row(
            children: [
              Expanded(
                child: _field(_port, 'Port', type: TextInputType.number),
              ),
              Checkbox(
                value: _ssl,
                onChanged: (v) => setState(() => _ssl = v ?? true),
              ),
              const Text('SSL / TLS'),
            ],
          ),
          _field(_folder, 'Folder to monitor'),
          _field(_username, 'Username (defaults to email)', required: false),
          _field(_password, 'Password / app password', obscure: true),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : _test,
                  child: const Text('Test connection'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _busy ? null : _save,
                  child: Text(_busy ? 'Working…' : 'Save'),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _field(
    TextEditingController controller,
    String label, {
    TextInputType? type,
    bool required = true,
    bool obscure = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      controller: controller,
      keyboardType: type,
      obscureText: obscure,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      validator: required
          ? (value) => value == null || value.trim().isEmpty
                ? '$label is required'
                : null
          : null,
    ),
  );
  @override
  void dispose() {
    _email.dispose();
    _host.dispose();
    _port.dispose();
    _username.dispose();
    _password.dispose();
    _folder.dispose();
    super.dispose();
  }
}
