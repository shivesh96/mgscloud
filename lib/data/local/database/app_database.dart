import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class AppDatabase {
  static final AppDatabase instance = AppDatabase._init();
  static Database? _database;

  AppDatabase._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('msg_to_server.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 6,
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
      onOpen: (db) async {
        // Guarantee column existence on every launch regardless of old DB version
        try {
          await db.execute(
            'ALTER TABLE otp_rules ADD COLUMN server_id INTEGER',
          );
        } catch (_) {}
        try {
          await db.execute(
            'ALTER TABLE otp_rules ADD COLUMN request_body_sample TEXT',
          );
        } catch (_) {}
        try {
          await db.execute('ALTER TABLE otp_rules ADD COLUMN raw_data TEXT');
        } catch (_) {}
        try {
          await db.execute(
            'ALTER TABLE app_settings ADD COLUMN send_filtered_only INTEGER NOT NULL DEFAULT 0',
          );
        } catch (_) {}
        try {
          await db.execute('ALTER TABLE events ADD COLUMN service_center TEXT');
        } catch (_) {}
        try {
          await db.execute('ALTER TABLE events ADD COLUMN otp TEXT');
        } catch (_) {}
        try {
          await db.execute('ALTER TABLE events ADD COLUMN user_id INTEGER');
        } catch (_) {}
        try {
          await db.execute('ALTER TABLE events ADD COLUMN target_mobile TEXT');
        } catch (_) {}
        try {
          await db.execute(
            "ALTER TABLE users ADD COLUMN role TEXT DEFAULT 'user'",
          );
        } catch (_) {}
        try {
          await db.execute(
            "ALTER TABLE users ADD COLUMN permissions TEXT DEFAULT 'send_events,view_logs'",
          );
        } catch (_) {}
        try {
          await db.execute(
            "ALTER TABLE users ADD COLUMN status TEXT DEFAULT 'active'",
          );
        } catch (_) {}
        try {
          await db.execute(
            "ALTER TABLE users ADD COLUMN device_status TEXT DEFAULT 'active'",
          );
        } catch (_) {}
        try {
          await db.execute(
            'ALTER TABLE events ADD COLUMN content_hidden INTEGER DEFAULT 0',
          );
        } catch (_) {}
        try {
          await db.execute(
            'ALTER TABLE events ADD COLUMN user_profile_id TEXT',
          );
        } catch (_) {}
        try {
          await db.execute(
            "ALTER TABLE sim_config ADD COLUMN number_source TEXT NOT NULL DEFAULT 'default'",
          );
        } catch (_) {}

        // Seed default OTP rules if table is empty
        try {
          final countRes = await db.rawQuery(
            'SELECT COUNT(*) as count FROM otp_rules',
          );
          final count = Sqflite.firstIntValue(countRes) ?? 0;
          if (count == 0) {
            final now = DateTime.now().millisecondsSinceEpoch;
            await db.insert('otp_rules', {
              'rule_name': 'Mobikwik_Login_OTP',
              'type': 'sms',
              'filter_name': 'OTP',
              'sender': 'MOBIK',
              'service_center': '',
              'body_pattern': '',
              'regex': r'(\d+)\s+is the OTP',
              'attribute': 'gm',
              'reg_index': 1,
              'enabled': 1,
              'updated_at': now,
            });
            await db.insert('otp_rules', {
              'rule_name': 'Generic_OTP_Code',
              'type': 'sms',
              'filter_name': 'OTP',
              'sender': '',
              'service_center': '',
              'body_pattern': '',
              'regex': r'(?:OTP|verification code|security code|passcode|code)\s*(?:is|:)?\s*([0-9]{4,8})',
              'attribute': 'i',
              'reg_index': 1,
              'enabled': 1,
              'updated_at': now,
            });
            await db.insert('otp_rules', {
              'rule_name': 'Leading_Digits_OTP',
              'type': 'sms',
              'filter_name': 'OTP',
              'sender': '',
              'service_center': '',
              'body_pattern': '',
              'regex': r'^([0-9]{4,8})\s+(?:is your|is the)',
              'attribute': 'i',
              'reg_index': 1,
              'enabled': 1,
              'updated_at': now,
            });
          }
        } catch (_) {}
      },
    );
  }

  Future<void> _createDB(Database db, int version) async {
    // Events table
    await db.execute('''
CREATE TABLE events (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  uuid TEXT NOT NULL UNIQUE,
  source TEXT NOT NULL,
  event_type TEXT NOT NULL,
  timestamp INTEGER NOT NULL,
  sim_slot INTEGER,
  sim_name TEXT,
  sim_number TEXT,
  sender TEXT,
  title TEXT,
  message TEXT NOT NULL,
  package_name TEXT,
  instance_name TEXT,
  user_phone_number TEXT,
  delivery_status TEXT NOT NULL,
  retry_count INTEGER NOT NULL DEFAULT 0,
  server_response TEXT,
  service_center TEXT,
  otp TEXT,
  user_id INTEGER,
  target_mobile TEXT,
  created_at INTEGER NOT NULL,
  content_hidden INTEGER DEFAULT 0,
  user_profile_id TEXT
)
''');

    // App Settings table
    await db.execute('''
CREATE TABLE app_settings (
  id INTEGER PRIMARY KEY CHECK (id = 1),
  server_url TEXT NOT NULL DEFAULT '',
  protocol TEXT NOT NULL DEFAULT 'WebSocket',
  http_method TEXT NOT NULL DEFAULT 'POST',
  auth_type TEXT NOT NULL DEFAULT 'NONE',
  auth_token TEXT NOT NULL DEFAULT '',
  connection_timeout INTEGER NOT NULL DEFAULT 30,
  retry_count INTEGER NOT NULL DEFAULT 3,
  retry_interval INTEGER NOT NULL DEFAULT 15,
  retention_days INTEGER NOT NULL DEFAULT 30,
  service_enabled INTEGER NOT NULL DEFAULT 1,
  send_filtered_only INTEGER NOT NULL DEFAULT 0
)
''');

    // Insert default settings
    await db.insert('app_settings', {
      'id': 1,
      'server_url': '',
      'protocol': 'WebSocket',
      'http_method': 'POST',
      'auth_type': 'NONE',
      'auth_token': '',
      'connection_timeout': 30,
      'retry_count': 3,
      'retry_interval': 15,
      'retention_days': 30,
      'service_enabled': 1,
    });

    // SIM Configuration table
    await db.execute('''
CREATE TABLE sim_config (
  subscription_id INTEGER PRIMARY KEY,
  slot_index INTEGER NOT NULL,
  carrier_name TEXT,
  default_name TEXT NOT NULL,
  custom_name TEXT,
  detected_number TEXT,
  user_phone_number TEXT,
  number_source TEXT NOT NULL DEFAULT 'default',
  enabled INTEGER NOT NULL DEFAULT 1,
  updated_at INTEGER NOT NULL
)
''');

    // WhatsApp & Clones Configuration table
    await db.execute('''
CREATE TABLE whatsapp_config (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  package_name TEXT NOT NULL,
  instance_name TEXT NOT NULL,
  phone_number TEXT NOT NULL DEFAULT '',
  is_clone INTEGER NOT NULL DEFAULT 0,
  enabled INTEGER NOT NULL DEFAULT 1,
  updated_at INTEGER NOT NULL
)
''');

    // Email Configuration table
    await db.execute('''
CREATE TABLE email_config (
  id INTEGER PRIMARY KEY CHECK (id = 1),
  email_address TEXT NOT NULL DEFAULT '',
  imap_host TEXT NOT NULL DEFAULT '',
  imap_port INTEGER NOT NULL DEFAULT 993,
  use_ssl INTEGER NOT NULL DEFAULT 1,
  username TEXT NOT NULL DEFAULT '',
  password TEXT NOT NULL DEFAULT '',
  folder TEXT NOT NULL DEFAULT 'INBOX',
  fetch_interval_minutes INTEGER NOT NULL DEFAULT 15,
  last_synced_at INTEGER,
  enabled INTEGER NOT NULL DEFAULT 0,
  updated_at INTEGER NOT NULL
)
''');

    // Insert default email config
    await db.insert('email_config', {
      'id': 1,
      'email_address': '',
      'imap_host': 'imap.gmail.com',
      'imap_port': 993,
      'use_ssl': 1,
      'username': '',
      'password': '',
      'folder': 'INBOX',
      'fetch_interval_minutes': 15,
      'last_synced_at': null,
      'enabled': 0,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    });

    // Processed Emails table to prevent duplicate ingestion
    await db.execute('''
CREATE TABLE processed_emails (
  message_id TEXT PRIMARY KEY,
  uid INTEGER,
  email_account TEXT NOT NULL,
  processed_at INTEGER NOT NULL
)
''');

    await _createEmailAccountTables(db);

    // Notification Source Config table
    await db.execute('''
CREATE TABLE source_config (
  package_name TEXT PRIMARY KEY,
  display_name TEXT NOT NULL,
  enabled INTEGER NOT NULL DEFAULT 1
)
''');

    // Users table for local session & authentication
    await db.execute('''
CREATE TABLE users (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  server_user_id INTEGER,
  username TEXT,
  mobile TEXT,
  email TEXT,
  auth_token TEXT,
  is_guest INTEGER NOT NULL DEFAULT 0,
  is_active INTEGER NOT NULL DEFAULT 1,
  created_at INTEGER NOT NULL
)
''');

    // Insert default Guest user
    await db.insert('users', {
      'id': 1,
      'server_user_id': null,
      'username': 'Guest User',
      'mobile': '',
      'email': '',
      'auth_token': '',
      'is_guest': 1,
      'is_active': 1,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });

    // User Bindings table (mobile/email to user account)
    await db.execute('''
CREATE TABLE user_bindings (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER,
  type TEXT NOT NULL,
  value TEXT NOT NULL,
  created_at INTEGER NOT NULL
)
''');

    // OTP Rules table
    await db.execute('''
CREATE TABLE otp_rules (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  server_id INTEGER,
  rule_name TEXT NOT NULL,
  type TEXT NOT NULL DEFAULT 'sms',
  filter_name TEXT NOT NULL DEFAULT 'OTP',
  sender TEXT,
  service_center TEXT,
  body_pattern TEXT,
  regex TEXT NOT NULL,
  attribute TEXT DEFAULT 'gm',
  reg_index INTEGER NOT NULL DEFAULT 1,
  enabled INTEGER NOT NULL DEFAULT 1,
  request_body_sample TEXT,
  raw_data TEXT,
  updated_at INTEGER NOT NULL
)
''');

    // Default OTP rules will be seeded or synced from server
    // await db.insert('otp_rules', {
    //   'rule_name': 'Mobikwik_Login_OTP',
    //   'type': 'sms',
    //   'filter_name': 'OTP',
    //   'sender': 'MOBIK',
    //   'service_center': '',
    //   'body_pattern': '',
    //   'regex': r'(\d+)\s+is the OTP',
    //   'attribute': 'gm',
    //   'reg_index': 1,
    //   'enabled': 1,
    //   'updated_at': now,
    // });

    // await db.insert('otp_rules', {
    //   'rule_name': 'Generic_OTP_Code',
    //   'type': 'sms',
    //   'filter_name': 'OTP',
    //   'sender': '',
    //   'service_center': '',
    //   'body_pattern': '',
    //   'regex': r'(?:OTP|verification code|security code|passcode|code)\s*(?:is|:)?\s*([0-9]{4,8})',
    //   'attribute': 'i',
    //   'reg_index': 1,
    //   'enabled': 1,
    //   'updated_at': now,
    // });

    // await db.insert('otp_rules', {
    //   'rule_name': 'Leading_Digits_OTP',
    //   'type': 'sms',
    //   'filter_name': 'OTP',
    //   'sender': '',
    //   'service_center': '',
    //   'body_pattern': '',
    //   'regex': r'^([0-9]{4,8})\s+(?:is your|is the)',
    //   'attribute': 'i',
    //   'reg_index': 1,
    //   'enabled': 1,
    //   'updated_at': now,
    // });
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('DROP TABLE IF EXISTS events');
      await db.execute('DROP TABLE IF EXISTS app_settings');
      await db.execute('DROP TABLE IF EXISTS sim_config');
      await db.execute('DROP TABLE IF EXISTS source_config');
      await _createDB(db, newVersion);
      return;
    }

    if (oldVersion < 3) {
      try {
        await db.execute('ALTER TABLE events ADD COLUMN service_center TEXT');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE events ADD COLUMN otp TEXT');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE events ADD COLUMN user_id INTEGER');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE events ADD COLUMN target_mobile TEXT');
      } catch (_) {}
      try {
        await db.execute(
          'ALTER TABLE app_settings ADD COLUMN send_filtered_only INTEGER NOT NULL DEFAULT 0',
        );
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE otp_rules ADD COLUMN server_id INTEGER');
      } catch (_) {}
      try {
        await db.execute(
          'ALTER TABLE otp_rules ADD COLUMN request_body_sample TEXT',
        );
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE otp_rules ADD COLUMN raw_data TEXT');
      } catch (_) {}
    }

    if (oldVersion < 4) {
      try {
        await db.execute('ALTER TABLE otp_rules ADD COLUMN server_id INTEGER');
      } catch (_) {}
      try {
        await db.execute(
          'ALTER TABLE otp_rules ADD COLUMN request_body_sample TEXT',
        );
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE otp_rules ADD COLUMN raw_data TEXT');
      } catch (_) {}
      try {
        await db.execute(
          'ALTER TABLE app_settings ADD COLUMN send_filtered_only INTEGER NOT NULL DEFAULT 0',
        );
      } catch (_) {}
    }

    if (oldVersion < 5) {
      await _createEmailAccountTables(db);
      // Migrate the former single account exactly once. Leaving the legacy
      // table intact makes this upgrade safe for interrupted older installs.
      final legacy = await db.query('email_config', where: 'id = 1', limit: 1);
      if (legacy.isNotEmpty) {
        final row = legacy.first;
        await db.insert('email_accounts', {
          'email_address': row['email_address'] ?? '',
          'imap_host': row['imap_host'] ?? '',
          'imap_port': row['imap_port'] ?? 993,
          'use_ssl': row['use_ssl'] ?? 1,
          'username': row['username'] ?? '',
          'password': row['password'] ?? '',
          'folder': row['folder'] ?? 'INBOX',
          'last_synced_at': row['last_synced_at'],
          'enabled': row['enabled'] ?? 0,
          'updated_at':
              row['updated_at'] ?? DateTime.now().millisecondsSinceEpoch,
        });
      }
    }

    if (oldVersion < 6) {
      // The legacy localhost example is not a configured server. Clearing it
      // forces a successful server-connection check followed by login.
      await db.update(
        'app_settings',
        {'server_url': ''},
        where: 'server_url = ?',
        whereArgs: ['http://127.0.0.1:8080/api/v1/events'],
      );
    }

    try {
      await db.execute(
        "ALTER TABLE sim_config ADD COLUMN number_source TEXT NOT NULL DEFAULT 'default'",
      );
    } catch (_) {}

    await db.execute('''
CREATE TABLE IF NOT EXISTS users (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  server_user_id INTEGER,
  username TEXT,
  mobile TEXT,
  email TEXT,
  auth_token TEXT,
  is_guest INTEGER NOT NULL DEFAULT 0,
  is_active INTEGER NOT NULL DEFAULT 1,
  created_at INTEGER NOT NULL
)
''');

    await db.execute('''
CREATE TABLE IF NOT EXISTS user_bindings (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER,
  type TEXT NOT NULL,
  value TEXT NOT NULL,
  created_at INTEGER NOT NULL
)
''');

    await db.execute('''
CREATE TABLE IF NOT EXISTS otp_rules (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  rule_name TEXT NOT NULL,
  type TEXT NOT NULL DEFAULT 'sms',
  filter_name TEXT NOT NULL DEFAULT 'OTP',
  sender TEXT,
  service_center TEXT,
  body_pattern TEXT,
  regex TEXT NOT NULL,
  attribute TEXT DEFAULT 'gm',
  reg_index INTEGER NOT NULL DEFAULT 1,
  enabled INTEGER NOT NULL DEFAULT 1,
  updated_at INTEGER NOT NULL
)
''');

    final count =
        Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM otp_rules'),
        ) ??
        0;
    if (count == 0) {
      final now = DateTime.now().millisecondsSinceEpoch;
      await db.insert('otp_rules', {
        'rule_name': 'Mobikwik_Login_OTP',
        'type': 'sms',
        'filter_name': 'OTP',
        'sender': 'MOBIK',
        'service_center': '',
        'body_pattern': '',
        'regex': r'(\d+)\s+is the OTP',
        'attribute': 'gm',
        'reg_index': 1,
        'enabled': 1,
        'updated_at': now,
      });
      await db.insert('otp_rules', {
        'rule_name': 'Generic_OTP_Code',
        'type': 'sms',
        'filter_name': 'OTP',
        'sender': '',
        'service_center': '',
        'body_pattern': '',
        'regex': r'(?:OTP|verification code|security code|passcode|code)\s*(?:is|:)?\s*([0-9]{4,8})',
        'attribute': 'i',
        'reg_index': 1,
        'enabled': 1,
        'updated_at': now,
      });
    }

    final userCount =
        Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM users'),
        ) ??
        0;
    if (userCount == 0) {
      await db.insert('users', {
        'id': 1,
        'server_user_id': null,
        'username': 'Guest User',
        'mobile': '',
        'email': '',
        'auth_token': '',
        'is_guest': 1,
        'is_active': 1,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });
    }
  }

  Future<void> close() async {
    final db = await instance.database;
    db.close();
  }

  Future<void> _createEmailAccountTables(Database db) async {
    await db.execute('''
CREATE TABLE IF NOT EXISTS email_accounts (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  email_address TEXT NOT NULL DEFAULT '',
  imap_host TEXT NOT NULL DEFAULT '',
  imap_port INTEGER NOT NULL DEFAULT 993,
  use_ssl INTEGER NOT NULL DEFAULT 1,
  username TEXT NOT NULL DEFAULT '',
  password TEXT NOT NULL DEFAULT '',
  folder TEXT NOT NULL DEFAULT 'INBOX',
  last_synced_at INTEGER,
  enabled INTEGER NOT NULL DEFAULT 0,
  updated_at INTEGER NOT NULL
)
''');
    await db.execute('''
CREATE TABLE IF NOT EXISTS processed_email_events (
  account_id INTEGER NOT NULL,
  uid_validity INTEGER NOT NULL,
  uid INTEGER NOT NULL,
  message_id TEXT,
  processed_at INTEGER NOT NULL,
  PRIMARY KEY (account_id, uid_validity, uid)
)
''');
  }
}
