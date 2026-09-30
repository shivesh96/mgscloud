
import 'dart:async';
import 'package:flutter/material.dart';
import '../../data/local/dao/event_dao.dart';
import '../../domain/models/event_model.dart';
import '../../domain/models/user_model.dart';
import '../../services/auth_service.dart';
import '../shared/event_detail_sheet.dart';

class LogsScreen extends StatefulWidget {
  const LogsScreen({super.key});

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  final EventDao _eventDao = EventDao();
  final AuthService _authService = AuthService.instance;

  List<EventModel> _logs = [];
  bool _isLoading = true;
  UserModel? _currentUser;
  StreamSubscription<UserModel>? _permSub;

  bool _selectionMode = false;
  final Set<int> _selectedIds = {};

  String _selectedSource = 'ALL';
  String _selectedStatus = 'ALL';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadUser();
    _loadLogs();

    _permSub = _authService.onUserPermissionsChanged.listen((user) {
      if (!mounted) return;
      setState(() => _currentUser = user);
      if (!user.canViewLogs) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Access revoked: You no longer have permission to view logs.'),
            backgroundColor: Colors.red,
          ),
        );
        Navigator.of(context).pop();
      }
    });
  }

  Future<void> _loadUser() async {
    final user = await _authService.getCurrentUser();
    if (mounted) {
      setState(() => _currentUser = user);
    }
  }

  Future<void> _loadLogs() async {
    setState(() => _isLoading = true);
    final results = await _eventDao.getAllEvents(
      source: _selectedSource,
      status: _selectedStatus,
      query: _searchController.text,
      limit: 100,
    );
    if (mounted) {
      setState(() {
        _logs = results;
        _isLoading = false;
      });
    }
  }

  void _showPermissionDenied(String action) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Permission Denied: You do not have permission to $action (delete_messages required).'),
        backgroundColor: Colors.red.shade700,
      ),
    );
  }

  Future<void> _deleteSingleEvent(EventModel event) async {
    if (_currentUser?.canDeleteLogs != true) {
      _showPermissionDenied('delete this log');
      _loadLogs();
      return;
    }

    if (event.id != null) {
      await _eventDao.deleteEvent(event.id!);
      _authService.deleteServerEvents(ids: [event.id!]);
      _loadLogs();
    }
  }

  Future<void> _deleteSelectedEvents() async {
    if (_currentUser?.canDeleteLogs != true) {
      _showPermissionDenied('delete selected logs');
      return;
    }
    if (_selectedIds.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Selected Logs'),
        content: Text('Are you sure you want to delete ${_selectedIds.length} selected message log(s)?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final idsToDelete = _selectedIds.toList();
      await _eventDao.deleteEventsByIds(idsToDelete);
      _authService.deleteServerEvents(ids: idsToDelete);
      setState(() {
        _selectionMode = false;
        _selectedIds.clear();
      });
      _loadLogs();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Deleted ${idsToDelete.length} logs successfully.')),
        );
      }
    }
  }

  Future<void> _deleteFilteredEvents() async {
    if (_currentUser?.canDeleteLogs != true) {
      _showPermissionDenied('delete filtered logs');
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Filtered (Non-OTP) Messages'),
        content: const Text(
          'This will remove all non-OTP messages that were filtered out from local storage and server records. Are you sure?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade800),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete Filtered', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final count = await _eventDao.deleteFilteredEvents();
      _authService.deleteServerEvents(type: 'filtered');
      _loadLogs();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Removed $count filtered message(s).')),
        );
      }
    }
  }

  Future<void> _confirmClearLogs() async {
    if (_currentUser?.canDeleteLogs != true) {
      _showPermissionDenied('clear all logs');
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear All Logs'),
        content: const Text('Are you sure you want to delete all stored event logs? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear All', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (ok == true) {
      await _eventDao.clearAllLogs();
      _authService.deleteServerEvents(all: true);
      setState(() {
        _selectionMode = false;
        _selectedIds.clear();
      });
      _loadLogs();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All logs cleared.')),
        );
      }
    }
  }

  void _toggleSelectAll() {
    setState(() {
      if (_selectedIds.length == _logs.length) {
        _selectedIds.clear();
      } else {
        _selectedIds.clear();
        for (final e in _logs) {
          if (e.id != null) _selectedIds.add(e.id!);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final canDelete = _currentUser?.canDeleteLogs ?? true;

    return Scaffold(
      appBar: AppBar(
        title: _selectionMode
            ? Text('${_selectedIds.length} selected')
            : const Text('Event Logs'),
        leading: _selectionMode
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: () {
                  setState(() {
                    _selectionMode = false;
                    _selectedIds.clear();
                  });
                },
              )
            : null,
        actions: _selectionMode
            ? [
                IconButton(
                  icon: Icon(_selectedIds.length == _logs.length && _logs.isNotEmpty
                      ? Icons.select_all
                      : Icons.deselect),
                  tooltip: _selectedIds.length == _logs.length ? 'Deselect All' : 'Select All',
                  onPressed: _logs.isEmpty ? null : _toggleSelectAll,
                ),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.redAccent),
                  tooltip: 'Delete Selected',
                  onPressed: _selectedIds.isEmpty ? null : _deleteSelectedEvents,
                ),
              ]
            : [
                if (canDelete)
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert),
                    tooltip: 'Message Actions',
                    onSelected: (val) {
                      switch (val) {
                        case 'select':
                          setState(() => _selectionMode = true);
                          break;
                        case 'filtered':
                          _deleteFilteredEvents();
                          break;
                        case 'clear':
                          _confirmClearLogs();
                          break;
                      }
                    },
                    itemBuilder: (ctx) => [
                      const PopupMenuItem(
                        value: 'select',
                        child: Row(
                          children: [
                            Icon(Icons.checklist, size: 20),
                            SizedBox(width: 8),
                            Text('Select Messages'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'filtered',
                        child: Row(
                          children: [
                            Icon(Icons.filter_alt_off_outlined, size: 20, color: Colors.orange),
                            SizedBox(width: 8),
                            Text('Delete Filtered (Non-OTP)'),
                          ],
                        ),
                      ),
                      const PopupMenuDivider(),
                      const PopupMenuItem(
                        value: 'clear',
                        child: Row(
                          children: [
                            Icon(Icons.delete_forever, size: 20, color: Colors.red),
                            SizedBox(width: 8),
                            Text('Clear All Logs', style: TextStyle(color: Colors.red)),
                          ],
                        ),
                      ),
                    ],
                  ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _loadLogs,
                ),
              ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search logs (sender, message, subject)...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          _loadLogs();
                        },
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onSubmitted: (_) => _loadLogs(),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Text('Source: ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                for (final s in ['ALL', 'sms', 'whatsapp', 'email'])
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(s.toUpperCase()),
                      selected: _selectedSource == s,
                      onSelected: (val) {
                        if (val) {
                          setState(() => _selectedSource = s);
                          _loadLogs();
                        }
                      },
                    ),
                  ),
                const SizedBox(width: 8),
                const Text('Status: ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                for (final st in ['ALL', 'sent', 'pending', 'failed'])
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(st.toUpperCase()),
                      selected: _selectedStatus == st,
                      onSelected: (val) {
                        if (val) {
                          setState(() => _selectedStatus = st);
                          _loadLogs();
                        }
                      },
                    ),
                  ),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _logs.isEmpty
                    ? const Center(child: Text('No events found.'))
                    : ListView.builder(
                        itemCount: _logs.length,
                        itemBuilder: (context, index) {
                          final event = _logs[index];
                          return _buildEventTile(event);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildEventTile(EventModel event) {
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

    final isSelected = event.id != null && _selectedIds.contains(event.id);

    final tile = ListTile(
      selected: isSelected,
      selectedTileColor: Theme.of(context).colorScheme.primary.withOpacity(0.08),
      onLongPress: () {
        if (!_selectionMode && event.id != null) {
          setState(() {
            _selectionMode = true;
            _selectedIds.add(event.id!);
          });
        }
      },
      onTap: () {
        if (_selectionMode) {
          if (event.id != null) {
            setState(() {
              if (_selectedIds.contains(event.id)) {
                _selectedIds.remove(event.id);
                if (_selectedIds.isEmpty) _selectionMode = false;
              } else {
                _selectedIds.add(event.id!);
              }
            });
          }
        } else {
          showEventDetailSheet(context, event);
        }
      },
      leading: _selectionMode
          ? Checkbox(
              value: isSelected,
              onChanged: (val) {
                if (event.id != null) {
                  setState(() {
                    if (val == true) {
                      _selectedIds.add(event.id!);
                    } else {
                      _selectedIds.remove(event.id);
                      if (_selectedIds.isEmpty) _selectionMode = false;
                    }
                  });
                }
              },
            )
          : CircleAvatar(
              backgroundColor: badgeColor.withOpacity(0.15),
              child: Icon(icon, color: badgeColor),
            ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              event.sender ?? event.title ?? 'Unknown',
              style: const TextStyle(fontWeight: FontWeight.bold),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              event.deliveryStatus.toUpperCase(),
              style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            event.message ?? '',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              if (event.simName != null || event.simSlot != null)
                Text(
                  '${event.simName ?? "SIM ${event.simSlot! + 1}"} • ',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              if (event.instanceName != null)
                Text(
                  '${event.instanceName} • ',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              Text(
                event.timestamp.split('T').last.split('.').first,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
            ],
          ),
        ],
      ),
      isThreeLine: true,
    );

    if (_selectionMode) {
      return tile;
    }

    return Dismissible(
      key: Key(event.eventId),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        color: Colors.red,
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) => _deleteSingleEvent(event),
      child: tile,
    );
  }

  @override
  void dispose() {
    _permSub?.cancel();
    _searchController.dispose();
    super.dispose();
  }
}
