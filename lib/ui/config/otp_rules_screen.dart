import 'dart:async';
import 'package:flutter/material.dart';
import '../../data/local/dao/otp_rule_dao.dart';
import '../../domain/models/otp_rule_model.dart';
import '../../domain/models/user_model.dart';
import '../../services/auth_service.dart';
import '../../services/otp_parser_service.dart';

class OtpRulesScreen extends StatefulWidget {
  const OtpRulesScreen({super.key});

  @override
  State<OtpRulesScreen> createState() => _OtpRulesScreenState();
}

class _OtpRulesScreenState extends State<OtpRulesScreen> {
  final OtpRuleDao _ruleDao = OtpRuleDao();
  final OtpParserService _parser = OtpParserService.instance;
  final AuthService _authService = AuthService.instance;

  List<OtpRuleModel> _rules = [];
  UserModel? _currentUser;
  StreamSubscription<UserModel>? _permSub;
  bool _isLoading = true;
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    _loadData();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncWithServer(silent: true);
    });

    _permSub = _authService.onUserPermissionsChanged.listen((user) {
      if (!mounted) return;
      setState(() => _currentUser = user);
      if (!user.canViewRules) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Access revoked: You no longer have permission to view rules.'),
            backgroundColor: Colors.red,
          ),
        );
        Navigator.of(context).pop();
      }
    });
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final user = await _authService.getCurrentUser();
    final rules = await _ruleDao.getAllRules();
    if (mounted) {
      setState(() {
        _currentUser = user;
        _rules = rules;
        _isLoading = false;
      });
    }
  }

  Future<void> _syncWithServer({bool silent = false}) async {
    if (_isSyncing) return;
    setState(() => _isSyncing = true);

    try {
      final res = await _parser.syncBidirectional();
      final updatedRules = await _ruleDao.getAllRules();
      if (mounted) {
        setState(() {
          _rules = updatedRules;
          _isSyncing = false;
        });
        if (!silent) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(res['message'] as String? ?? 'Rules synced with server.'),
              backgroundColor: res['success'] == true ? Colors.green : Colors.orange,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSyncing = false);
        if (!silent) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Sync failed: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Future<void> _toggleRule(OtpRuleModel rule, bool value) async {
    if (!(_currentUser?.canManageRules ?? false)) {
      _showPermissionDenied();
      return;
    }
    if (rule.id == null) return;
    await _ruleDao.toggleRule(rule.id!, value);
    _parser.invalidateCache();
    _parser.updateRuleOnServer(rule.copyWith(enabled: value));
    _loadData();
  }

  Future<void> _deleteRule(OtpRuleModel rule) async {
    if (!(_currentUser?.canManageRules ?? false)) {
      _showPermissionDenied();
      return;
    }
    if (rule.id == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Rule'),
        content: Text('Are you sure you want to delete "${rule.ruleName}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    await _ruleDao.deleteRule(rule.id!);
    _parser.invalidateCache();
    _parser.deleteRuleFromServer(rule);
    _loadData();
  }

  void _showPermissionDenied() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Permission Denied: Your account (${_currentUser?.role.toUpperCase()}) does not have permission to manage rules.'),
        backgroundColor: Colors.red.shade800,
      ),
    );
  }

  void _showAddOrEditDialog({OtpRuleModel? existing}) {
    if (!(_currentUser?.canManageRules ?? false)) {
      _showPermissionDenied();
      return;
    }

    final nameCtrl = TextEditingController(text: existing?.ruleName ?? '');
    final typeCtrl = TextEditingController(text: existing?.type ?? 'sms');
    final filterCtrl = TextEditingController(text: existing?.filterName ?? 'OTP');
    final senderCtrl = TextEditingController(text: existing?.sender ?? '');
    final scCtrl = TextEditingController(text: existing?.serviceCenter ?? '');
    final regexCtrl = TextEditingController(text: existing?.regex ?? r'(\d{4,8})');
    final indexCtrl = TextEditingController(text: (existing?.regIndex ?? 1).toString());
    final sampleCtrl = TextEditingController(text: existing?.requestBodySample ?? '');
    final rawDataCtrl = TextEditingController(text: existing?.rawData ?? '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existing == null ? 'Add OTP Parsing Rule' : 'Edit OTP Rule'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Rule Name (e.g. Mobikwik_Login_OTP)', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: ['sms', 'whatsapp', 'email', 'all'].contains(typeCtrl.text.toLowerCase()) ? typeCtrl.text.toLowerCase() : 'sms',
                decoration: const InputDecoration(labelText: 'Type / Channel', border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: 'sms', child: Text('SMS')),
                  DropdownMenuItem(value: 'whatsapp', child: Text('WhatsApp')),
                  DropdownMenuItem(value: 'email', child: Text('Email')),
                  DropdownMenuItem(value: 'all', child: Text('All Sources')),
                ],
                onChanged: (val) => typeCtrl.text = val ?? 'sms',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: senderCtrl,
                decoration: const InputDecoration(labelText: 'Sender (Leave empty for any, e.g. MOBIK)', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: scCtrl,
                decoration: const InputDecoration(labelText: 'Service Center (Optional)', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: regexCtrl,
                decoration: const InputDecoration(
                  labelText: 'Regex Pattern (Capture OTP with parentheses)',
                  hintText: r'(\d+)\s+is the OTP',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: indexCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Capture Group Index (Usually 1)', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: sampleCtrl,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Request Body Sample (Optional)', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: rawDataCtrl,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Raw Data (Optional)', border: OutlineInputBorder()),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final name = nameCtrl.text.trim();
              final regex = regexCtrl.text.trim();
              final index = int.tryParse(indexCtrl.text.trim()) ?? 1;

              if (name.isNotEmpty && regex.isNotEmpty) {
                final model = OtpRuleModel(
                  id: existing?.id,
                  serverId: existing?.serverId,
                  ruleName: name,
                  type: typeCtrl.text.trim(),
                  filterName: filterCtrl.text.trim(),
                  sender: senderCtrl.text.trim(),
                  serviceCenter: scCtrl.text.trim(),
                  regex: regex,
                  attribute: 'gm',
                  regIndex: index,
                  enabled: existing?.enabled ?? true,
                  requestBodySample: sampleCtrl.text.trim(),
                  rawData: rawDataCtrl.text.trim(),
                  updatedAt: DateTime.now().millisecondsSinceEpoch,
                );

                if (existing == null) {
                  final newId = await _ruleDao.insertRule(model);
                  final savedWithId = model.copyWith(id: newId);
                  _parser.pushRuleToServer(savedWithId);
                } else {
                  await _ruleDao.updateRule(model);
                  _parser.updateRuleOnServer(model);
                }
                _parser.invalidateCache();
                if (ctx.mounted) Navigator.of(ctx).pop();
                _loadData();
              }
            },
            child: Text(existing == null ? 'Add Rule' : 'Save Changes'),
          ),
        ],
      ),
    );
  }

  void _showTestRegexDialog() {
    final sampleCtrl = TextEditingController(text: '819413 is the OTP to complete your MobiKwik wallet login.');
    final senderCtrl = TextEditingController(text: 'MOBIK');
    final customRegexCtrl = TextEditingController(text: r'(?:OTP|code)\s*(?:is|:)?\s*([0-9]{4,8})');
    final customIndexCtrl = TextEditingController(text: '1');

    int tabIndex = 0;
    String? matchedRuleName;
    String? extractedResult;
    String? diagnosticInfo;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('OTP Regex Diagnostics & Tester'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    ChoiceChip(
                      label: const Text('Active Rules'),
                      selected: tabIndex == 0,
                      onSelected: (s) => setDialogState(() {
                        tabIndex = 0;
                        extractedResult = null;
                        diagnosticInfo = null;
                      }),
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text('Custom Regex'),
                      selected: tabIndex == 1,
                      onSelected: (s) => setDialogState(() {
                        tabIndex = 1;
                        extractedResult = null;
                        diagnosticInfo = null;
                      }),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                if (tabIndex == 0) ...[
                  TextField(
                    controller: senderCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Sender Match (Optional)',
                      hintText: 'e.g. MOBIK or HDFCBK',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: sampleCtrl,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Sample Message Body',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Center(
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        _parser.invalidateCache();
                        final rules = await _ruleDao.getActiveRules();
                        final body = sampleCtrl.text.trim();
                        final sender = senderCtrl.text.trim();

                        String? foundOtp;
                        String? matchedRule;

                        for (final r in rules) {
                          // Check sender match if configured
                          if (r.sender != null && r.sender!.trim().isNotEmpty) {
                            if (sender.isNotEmpty && !sender.toLowerCase().contains(r.sender!.toLowerCase()) &&
                                !r.sender!.toLowerCase().contains(sender.toLowerCase())) {
                              continue;
                            }
                          }

                          try {
                            final reg = RegExp(
                              r.regex,
                              multiLine: r.attribute.contains('m'),
                              caseSensitive: !r.attribute.contains('i'),
                            );
                            final match = reg.firstMatch(body);
                            if (match != null) {
                              final groupIdx = r.regIndex;
                              if (groupIdx <= match.groupCount && match.group(groupIdx) != null) {
                                foundOtp = match.group(groupIdx);
                                matchedRule = r.ruleName;
                                break;
                              }
                            }
                          } catch (_) {}
                        }

                        setDialogState(() {
                          matchedRuleName = matchedRule;
                          extractedResult = foundOtp;
                          diagnosticInfo = foundOtp != null
                              ? 'Matched rule: "$matchedRule"'
                              : 'Checked ${rules.length} active rules. No pattern matched this message.';
                        });
                      },
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Test Active Rules'),
                    ),
                  ),
                ] else ...[
                  TextField(
                    controller: customRegexCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Custom Regex Pattern',
                      hintText: r'(\d{4,8}) is your OTP',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: customIndexCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Capture Group Index',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: sampleCtrl,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Sample Text to Match',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Center(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        final pattern = customRegexCtrl.text.trim();
                        final groupIdx = int.tryParse(customIndexCtrl.text.trim()) ?? 1;
                        final body = sampleCtrl.text;

                        try {
                          final reg = RegExp(pattern, caseSensitive: false);
                          final match = reg.firstMatch(body);
                          if (match != null) {
                            if (groupIdx <= match.groupCount && match.group(groupIdx) != null) {
                              setDialogState(() {
                                matchedRuleName = 'Custom Regex';
                                extractedResult = match.group(groupIdx);
                                diagnosticInfo = 'Group $groupIdx captured successfully!';
                              });
                            } else {
                              setDialogState(() {
                                matchedRuleName = null;
                                extractedResult = null;
                                diagnosticInfo = 'Pattern matched full text, but Group $groupIdx was not captured (max group: ${match.groupCount}).';
                              });
                            }
                          } else {
                            setDialogState(() {
                              matchedRuleName = null;
                              extractedResult = null;
                              diagnosticInfo = 'Regex pattern did not match sample text.';
                            });
                          }
                        } catch (e) {
                          setDialogState(() {
                            matchedRuleName = null;
                            extractedResult = null;
                            diagnosticInfo = 'Regex Syntax Error: $e';
                          });
                        }
                      },
                      icon: const Icon(Icons.flash_on),
                      label: const Text('Evaluate Custom Regex'),
                    ),
                  ),
                ],

                const SizedBox(height: 16),
                if (diagnosticInfo != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: extractedResult != null ? Colors.green.shade50 : Colors.red.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: extractedResult != null ? Colors.green : Colors.red),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          matchedRuleName != null ? 'Match Found: $matchedRuleName' : (extractedResult != null ? 'Match Found!' : 'No Match'),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: extractedResult != null ? Colors.green.shade900 : Colors.red.shade900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          diagnosticInfo!,
                          style: TextStyle(fontSize: 12, color: extractedResult != null ? Colors.green.shade800 : Colors.red.shade800),
                        ),
                        if (extractedResult != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            extractedResult!,
                            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, letterSpacing: 2, color: Colors.green),
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canManage = _currentUser?.canManageRules ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('OTP Parsing Rules'),
        actions: [
          IconButton(
            icon: _isSyncing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  )
                : const Icon(Icons.sync),
            tooltip: 'Sync Rules with Server (2-Way)',
            onPressed: _isSyncing ? null : () => _syncWithServer(silent: false),
          ),
          IconButton(
            icon: const Icon(Icons.bug_report_outlined),
            tooltip: 'Test Regex Rules',
            onPressed: _showTestRegexDialog,
          ),
        ],
      ),
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              onPressed: () => _showAddOrEditDialog(),
              icon: const Icon(Icons.add),
              label: const Text('New Rule'),
            )
          : null,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => _syncWithServer(silent: false),
              child: ListView(
                padding: const EdgeInsets.all(16),
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  _buildPermissionNoticeBanner(canManage),
                  const SizedBox(height: 12),
                  _buildInfoBanner(),
                  const SizedBox(height: 16),
                  if (_rules.isEmpty)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32.0),
                        child: Text('No OTP rules defined yet.\nTap + or pull to sync from server.', textAlign: TextAlign.center),
                      ),
                    )
                  else
                    ..._rules.map((rule) => _buildRuleCard(rule, canManage)),
                ],
              ),
            ),
    );
  }

  Widget _buildPermissionNoticeBanner(bool canManage) {
    if (canManage) {
      return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.green.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.green.shade200),
        ),
        child: Row(
          children: [
            Icon(Icons.check_circle_outline, size: 18, color: Colors.green.shade800),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Permission Granted: You have full access to add, edit, and toggle OTP parsing rules.',
                style: TextStyle(fontSize: 12, color: Colors.green.shade900, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.orange.shade300),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_outline, size: 20, color: Colors.orange.shade900),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Read-Only Mode (manage_rules permission required)',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.orange.shade900),
                ),
                const SizedBox(height: 2),
                Text(
                  'Your account (${_currentUser?.username ?? "User"}, role: ${_currentUser?.role.toUpperCase() ?? "USER"}) is not permitted to create, edit, or delete rules. Contact an administrator to update rules.',
                  style: TextStyle(fontSize: 11, color: Colors.orange.shade900),
                ),
              ],
            ),
          ),
        ],
      ),
    );
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
          Icon(Icons.sync_alt, color: Colors.blue.shade700),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Rules sync bidirectionally with the server. Local changes are uploaded, and server rules are fetched automatically.',
              style: TextStyle(fontSize: 12, color: Colors.blue.shade900),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRuleCard(OtpRuleModel rule, bool canManage) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.vpn_key_outlined, color: rule.enabled ? Colors.indigo : Colors.grey),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        rule.ruleName,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.indigo.shade50,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              rule.type.toUpperCase(),
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.indigo.shade700),
                            ),
                          ),
                          const SizedBox(width: 6),
                          if (rule.serverId != null)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.green.shade50,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.cloud_done, size: 11, color: Colors.green.shade700),
                                  const SizedBox(width: 3),
                                  Text(
                                    'Server #${rule.serverId}',
                                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.green.shade700),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: rule.enabled,
                  onChanged: canManage ? (v) => _toggleRule(rule, v) : null,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Regex: ${rule.regex}', style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (rule.sender != null && rule.sender!.isNotEmpty)
                        Text('Sender: ${rule.sender}   ', style: const TextStyle(fontSize: 12, color: Colors.black54)),
                      Text('Group Index: ${rule.regIndex}', style: const TextStyle(fontSize: 12, color: Colors.black54)),
                    ],
                  ),
                  if (rule.requestBodySample != null && rule.requestBodySample!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Sample: ${rule.requestBodySample}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Colors.black54),
                    ),
                  ],
                ],
              ),
            ),
            if (canManage) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: () => _showAddOrEditDialog(existing: rule),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Edit'),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
                    onPressed: () => _deleteRule(rule),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _permSub?.cancel();
    super.dispose();
  }
}
