import 'dart:async';

import 'package:enough_mail/enough_mail.dart';

import '../data/local/dao/email_dao.dart';
import '../domain/models/email_config_model.dart';
import 'event_coordinator.dart';
import 'auth_service.dart';

/// Owns one long-lived IMAP IDLE session per enabled account.
///
/// The service deliberately does not use a timer to look for mail. A timer is
/// only used to renew an IDLE command before servers' 30-minute IDLE limit.
class EmailReaderService {
  static final EmailReaderService instance = EmailReaderService._init();
  final EmailDao _emailDao = EmailDao();
  final Map<int, _EmailIdleListener> _listeners = {};

  EmailReaderService._init();

  Future<void> startAllListeners() async {
    if (!await AuthService.instance.isAuthenticated()) {
      await stopAllListeners();
      return;
    }
    final accounts = await _emailDao.getEnabledEmailConfigs();
    final desiredIds = accounts.map((account) => account.id!).toSet();
    for (final entry in List<MapEntry<int, _EmailIdleListener>>.from(
      _listeners.entries,
    )) {
      if (!desiredIds.contains(entry.key)) {
        await entry.value.stop();
        _listeners.remove(entry.key);
      }
    }
    for (final account in accounts) {
      final id = account.id!;
      final current = _listeners[id];
      if (current == null || current.config.updatedAt != account.updatedAt) {
        await current?.stop();
        final listener = _EmailIdleListener(account, _ingestMessage);
        _listeners[id] = listener;
        unawaited(listener.start());
      }
    }
  }

  Future<void> stopAllListeners() async {
    final listeners = List<_EmailIdleListener>.from(_listeners.values);
    _listeners.clear();
    for (final listener in listeners) {
      await listener.stop();
    }
  }

  Future<void> refreshListeners() => startAllListeners();

  Future<Map<String, dynamic>> testConnection(EmailConfigModel config) async {
    if (config.imapHost.trim().isEmpty ||
        config.username.trim().isEmpty ||
        config.password.trim().isEmpty) {
      return {
        'success': false,
        'message': 'IMAP host, username, and password are required',
      };
    }
    final client = ImapClient(isLogEnabled: false);
    try {
      await client.connectToServer(
        config.imapHost.trim(),
        config.imapPort,
        isSecure: config.useSsl,
      );
      await client.login(config.username.trim(), config.password.trim());
      final mailbox = await client.selectMailboxByPath(_folder(config));
      await client.logout();
      return {
        'success': true,
        'message':
            'Connected successfully. ${mailbox.messagesExists} messages are in ${_folder(config)}.',
      };
    } catch (e) {
      try {
        await client.disconnect();
      } catch (_) {}
      return {
        'success': false,
        'message': 'IMAP error: ${e.toString().replaceAll('\n', ' ')}',
      };
    }
  }

  /// A user-requested catch-up, not the background delivery mechanism.
  Future<Map<String, dynamic>> syncEmailsNow() async {
    await startAllListeners();
    var count = 0;
    for (final listener in _listeners.values) {
      count += await listener.catchUp();
    }
    return {
      'success': true,
      'count': count,
      'message': count == 0
          ? 'All monitored inboxes are up to date.'
          : 'Sent $count new email(s).',
    };
  }

  Future<int> _ingestMessage(
    EmailConfigModel account,
    int uidValidity,
    MimeMessage message,
  ) async {
    final accountId = account.id!;
    final uid = message.uid;
    if (uid == null ||
        await _emailDao.isEmailProcessed(accountId, uidValidity, uid)) {
      return 0;
    }

    final envelope = message.envelope;
    final messageId =
        envelope?.messageId ?? 'uidvalidity-$uidValidity-uid-$uid';
    final from = envelope?.from?.isNotEmpty == true
        ? envelope!.from!.first.email
        : 'Unknown sender';
    final fromName = envelope?.from?.isNotEmpty == true
        ? (envelope!.from!.first.personalName ?? from)
        : from;
    final subject = envelope?.subject ?? '(No Subject)';
    final text =
        message.decodeTextPlainPart() ?? message.decodeTextHtmlPart() ?? '';
    final snippet = text.length > 500 ? text.substring(0, 500) : text;
    // Route email through the same coordinator as SMS. That applies configured
    // email OTP rules and the global "Forward all messages" switch consistently.
    await EventCoordinator.instance.processIncomingNativeEvent({
      'event_id': 'email-$accountId-$uidValidity-$uid',
      'event_type': 'email_received',
      'source': 'email',
      'timestamp':
          (message.decodeDate() ?? DateTime.now()).millisecondsSinceEpoch,
      'sender': fromName.isNotEmpty ? '$fromName <$from>' : from,
      'title': subject,
      'message': snippet.isNotEmpty ? snippet : subject,
      'package_name': account.emailAddress,
      'instance_name': 'Email (${account.emailAddress})',
      'user_phone_number': account.emailAddress,
    });
    await _emailDao.markEmailProcessed(accountId, uidValidity, uid, messageId);
    return 1;
  }

  static String _folder(EmailConfigModel config) =>
      config.folder.trim().isEmpty ? 'INBOX' : config.folder.trim();
}

class _EmailIdleListener {
  _EmailIdleListener(this.config, this._onMessage);

  final EmailConfigModel config;
  final Future<int> Function(EmailConfigModel, int, MimeMessage) _onMessage;
  final EmailDao _dao = EmailDao();
  ImapClient? _client;
  StreamSubscription<ImapEvent>? _events;
  Timer? _renewIdleTimer;
  Timer? _reconnectTimer;
  bool _stopped = false;
  bool _catchingUp = false;
  int _knownMessageCount = 0;
  int _uidValidity = 0;

  Future<void> start() async {
    _stopped = false;
    await _connect();
  }

  Future<void> stop() async {
    _stopped = true;
    _renewIdleTimer?.cancel();
    _reconnectTimer?.cancel();
    await _events?.cancel();
    _events = null;
    final client = _client;
    _client = null;
    if (client != null) {
      try {
        await client.idleDone();
      } catch (_) {}
      try {
        await client.logout();
      } catch (_) {}
      try {
        await client.disconnect();
      } catch (_) {}
    }
  }

  Future<int> catchUp() async {
    if (_stopped) return 0;
    if (_client == null || !_client!.isConnected) {
      await _connect();
      return 0;
    }
    return _fetchNewMessages();
  }

  Future<void> _connect() async {
    if (_stopped) return;
    await _events?.cancel();
    final client = ImapClient(isLogEnabled: false);
    _client = client;
    try {
      await client.connectToServer(
        config.imapHost.trim(),
        config.imapPort,
        isSecure: config.useSsl,
      );
      await client.login(config.username.trim(), config.password.trim());
      final box = await client.selectMailboxByPath(
        EmailReaderService._folder(config),
      );
      _knownMessageCount = box.messagesExists;
      _uidValidity = box.uidValidity ?? 0;
      _events = client.eventBus.on<ImapEvent>().listen(_handleImapEvent);
      // Catch up after a reconnect. UIDVALIDITY + UID is a durable key, so this
      // cannot resend mail that was already accepted before a dropped session.
      await _fetchNewMessages();
      if (!client.serverInfo.supportsIdle) {
        throw StateError('The IMAP server does not support IDLE');
      }
      await client.idleStart();
      _renewIdleTimer?.cancel();
      _renewIdleTimer = Timer.periodic(
        const Duration(minutes: 25),
        (_) => _renewIdle(),
      );
    } catch (_) {
      try {
        await client.disconnect();
      } catch (_) {}
      if (identical(_client, client)) _client = null;
      _scheduleReconnect();
    }
  }

  void _handleImapEvent(ImapEvent event) {
    if (_stopped) return;
    if (event is ImapConnectionLostEvent) {
      _scheduleReconnect();
    } else if (event is ImapMessagesExistEvent) {
      _knownMessageCount = event.newMessagesExists;
      unawaited(_fetchNewMessages());
    }
  }

  Future<void> _renewIdle() async {
    final client = _client;
    if (_stopped || client == null) return;
    try {
      await client.idleDone();
      await client.idleStart();
    } catch (_) {
      _scheduleReconnect();
    }
  }

  Future<int> _fetchNewMessages() async {
    final client = _client;
    if (_catchingUp || _stopped || client == null || !client.isConnected) {
      return 0;
    }
    _catchingUp = true;
    try {
      try {
        await client.idleDone();
      } catch (_) {}
      final box = await client.noop();
      final total = box?.messagesExists ?? _knownMessageCount;
      final first = total > 50 ? total - 49 : 1;
      var count = 0;
      if (total >= first) {
        final result = await client.fetchMessages(
          MessageSequence.fromRange(first, total),
          '(BODY.PEEK[] ENVELOPE UID)',
        );
        for (final message in result.messages) {
          count += await _onMessage(config, _uidValidity, message);
        }
      }
      _knownMessageCount = total;
      await _dao.updateLastSynced(
        config.id!,
        DateTime.now().millisecondsSinceEpoch,
      );
      if (!_stopped && client.isConnected) await client.idleStart();
      return count;
    } catch (_) {
      _scheduleReconnect();
      return 0;
    } finally {
      _catchingUp = false;
    }
  }

  void _scheduleReconnect() {
    if (_stopped || _reconnectTimer?.isActive == true) return;
    _renewIdleTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), _connect);
  }
}
