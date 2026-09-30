class UserModel {
  final int? id;
  final int? serverUserId;
  final String username;
  final String mobile;
  final String email;
  final String authToken;
  final String role; // 'user', 'operator', 'admin'
  final List<String> permissions; // e.g. ['manage_rules', 'send_events', 'view_logs']
  final String status; // 'active', 'blocked', 'inactive'
  final String deviceStatus; // 'active', 'blocked'
  final bool isGuest;
  final bool isActive;
  final int createdAt;

  UserModel({
    this.id,
    this.serverUserId,
    required this.username,
    required this.mobile,
    required this.email,
    this.authToken = '',
    this.role = 'user',
    this.permissions = const ['send_events', 'view_logs'],
    this.status = 'active',
    this.deviceStatus = 'active',
    this.isGuest = false,
    this.isActive = true,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'server_user_id': serverUserId,
      'username': username,
      'mobile': mobile,
      'email': email,
      'auth_token': authToken,
      'role': role,
      'permissions': permissions.join(','),
      'status': status,
      'device_status': deviceStatus,
      'is_guest': isGuest ? 1 : 0,
      'is_active': isActive ? 1 : 0,
      'created_at': createdAt,
    };
  }

  factory UserModel.fromMap(Map<String, dynamic> map) {
    final permsRaw = map['permissions'];
    List<String> perms = [];
    if (permsRaw is List) {
      perms = permsRaw.map((e) => e.toString().trim()).toList();
    } else if (permsRaw is String && permsRaw.isNotEmpty) {
      perms = permsRaw.split(',').map((e) => e.trim()).toList();
    } else {
      perms = ['send_events', 'view_logs'];
    }

    return UserModel(
      id: map['id'] as int?,
      serverUserId: map['server_user_id'] as int?,
      username: map['username'] as String? ?? 'User',
      mobile: map['mobile'] as String? ?? '',
      email: map['email'] as String? ?? '',
      authToken: map['auth_token'] as String? ?? '',
      role: map['role'] as String? ?? 'user',
      permissions: perms,
      status: map['status'] as String? ?? 'active',
      deviceStatus: map['device_status'] as String? ?? 'active',
      isGuest: map['is_guest'] == 1 || map['is_guest'] == true || map['is_guest'] == '1',
      isActive: map['is_active'] == null || map['is_active'] == 1 || map['is_active'] == true || map['is_active'] == '1',
      createdAt: map['created_at'] as int? ?? DateTime.now().millisecondsSinceEpoch,
    );
  }

  UserModel copyWith({
    int? id,
    int? serverUserId,
    String? username,
    String? mobile,
    String? email,
    String? authToken,
    String? role,
    List<String>? permissions,
    String? status,
    String? deviceStatus,
    bool? isGuest,
    bool? isActive,
    int? createdAt,
  }) {
    return UserModel(
      id: id ?? this.id,
      serverUserId: serverUserId ?? this.serverUserId,
      username: username ?? this.username,
      mobile: mobile ?? this.mobile,
      email: email ?? this.email,
      authToken: authToken ?? this.authToken,
      role: role ?? this.role,
      permissions: permissions ?? this.permissions,
      status: status ?? this.status,
      deviceStatus: deviceStatus ?? this.deviceStatus,
      isGuest: isGuest ?? this.isGuest,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  int? get effectiveUserId => isGuest ? null : (serverUserId ?? id);

  bool get isAdmin => role.toLowerCase() == 'admin' || role.toLowerCase() == 'super admin';
  bool get canManageRules => isGuest || isAdmin || permissions.contains('*') || permissions.contains('all') || permissions.contains('manage_rules');
  bool get canSendEvents => isGuest || isAdmin || permissions.contains('*') || permissions.contains('all') || permissions.contains('send_events');
  bool get canViewLogs => isGuest || isAdmin || permissions.contains('*') || permissions.contains('all') || permissions.contains('view_logs');
  bool get canDeleteLogs => isGuest || isAdmin || permissions.contains('*') || permissions.contains('all') || permissions.contains('delete_logs') || permissions.contains('delete_messages');
  bool get canManageSettings => isGuest || isAdmin || permissions.contains('*') || permissions.contains('all') || permissions.contains('manage_settings');
  bool get canControlService => isGuest || isAdmin || permissions.contains('*') || permissions.contains('all') || permissions.contains('control_service');
  bool get canViewRules => isGuest || isAdmin || permissions.contains('*') || permissions.contains('all') || permissions.contains('view_rules') || permissions.contains('manage_rules');
  bool get canViewMessages => isGuest || isAdmin || permissions.contains('*') || permissions.contains('all') || permissions.contains('view_messages') || permissions.contains('view_logs');

  bool hasPermission(String perm) => isAdmin || permissions.contains('*') || permissions.contains('all') || permissions.contains(perm);
  bool get isBlocked => status == 'blocked' || deviceStatus == 'blocked';
}
