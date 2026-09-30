class EmailConfigModel {
  final int? id;
  final String emailAddress;
  final String imapHost;
  final int imapPort;
  final bool useSsl;
  final String username;
  final String password;
  final String folder;
  final int? lastSyncedAt;
  final bool enabled;
  final int updatedAt;

  EmailConfigModel({
    this.id,
    this.emailAddress = '',
    this.imapHost = 'imap.gmail.com',
    this.imapPort = 993,
    this.useSsl = true,
    this.username = '',
    this.password = '',
    this.folder = 'INBOX',
    this.lastSyncedAt,
    this.enabled = false,
    required this.updatedAt,
  });

  /// IMAP UIDs are only unique within one mailbox/account.
  String get accountKey => id?.toString() ?? '';

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'email_address': emailAddress,
      'imap_host': imapHost,
      'imap_port': imapPort,
      'use_ssl': useSsl ? 1 : 0,
      'username': username,
      'password': password,
      'folder': folder,
      'last_synced_at': lastSyncedAt,
      'enabled': enabled ? 1 : 0,
      'updated_at': updatedAt,
    };
  }

  factory EmailConfigModel.fromMap(Map<String, dynamic> map) {
    return EmailConfigModel(
      id: map['id'] as int?,
      emailAddress: map['email_address'] as String? ?? '',
      imapHost: map['imap_host'] as String? ?? 'imap.gmail.com',
      imapPort: map['imap_port'] as int? ?? 993,
      useSsl: (map['use_ssl'] as int? ?? 1) == 1,
      username: map['username'] as String? ?? '',
      password: map['password'] as String? ?? '',
      folder: map['folder'] as String? ?? 'INBOX',
      lastSyncedAt: map['last_synced_at'] as int?,
      enabled: (map['enabled'] as int? ?? 0) == 1,
      updatedAt:
          map['updated_at'] as int? ?? DateTime.now().millisecondsSinceEpoch,
    );
  }

  EmailConfigModel copyWith({
    int? id,
    String? emailAddress,
    String? imapHost,
    int? imapPort,
    bool? useSsl,
    String? username,
    String? password,
    String? folder,
    int? lastSyncedAt,
    bool? enabled,
  }) {
    return EmailConfigModel(
      id: id ?? this.id,
      emailAddress: emailAddress ?? this.emailAddress,
      imapHost: imapHost ?? this.imapHost,
      imapPort: imapPort ?? this.imapPort,
      useSsl: useSsl ?? this.useSsl,
      username: username ?? this.username,
      password: password ?? this.password,
      folder: folder ?? this.folder,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      enabled: enabled ?? this.enabled,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
  }
}
