import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../data/local/dao/settings_dao.dart';
import '../data/local/dao/user_dao.dart';
import '../domain/models/user_model.dart';
import '../domain/models/user_binding_model.dart';
import 'native_service.dart';

class AuthService {
  static final AuthService instance = AuthService._init();
  final UserDao _userDao = UserDao();
  final SettingsDao _settingsDao = SettingsDao();
  final Dio _dio = Dio();

  UserModel? _currentUser;
  Timer? _autoRefreshTimer;

  final StreamController<UserModel> _userPermsController =
      StreamController<UserModel>.broadcast();
  Stream<UserModel> get onUserPermissionsChanged => _userPermsController.stream;

  AuthService._init() {
    startPeriodicPermissionRefresh();
  }

  void startPeriodicPermissionRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 35), (_) {
      validateAndRefreshUser();
    });
  }

  Future<UserModel> getCurrentUser() async {
    if (_currentUser != null) return _currentUser!;
    final user = await _userDao.getActiveUser();
    if (user != null) {
      _currentUser = user;
      return user;
    }
    // Default guest
    await _userDao.setGuestMode();
    _currentUser = await _userDao.getActiveUser();
    return _currentUser!;
  }

  /// Event delivery and server configuration are available only to a valid,
  /// non-guest session. Keeping this in one place prevents public rule/config
  /// requests from background workers started before login.
  Future<bool> isAuthenticated() async {
    final user = await getCurrentUser();
    return !user.isGuest &&
        user.authToken.isNotEmpty &&
        user.isActive &&
        !user.isBlocked;
  }

  Future<int?> getEffectiveUserId() async {
    final user = await getCurrentUser();
    return user.effectiveUserId;
  }

  Future<Map<String, dynamic>> login({
    required String identifier,
    required String password,
  }) async {
    final settings = await _settingsDao.getSettings();
    final serverUrl = settings['server_url'] as String? ?? '';

    if (serverUrl.trim().isEmpty) {
      return {
        'success': false,
        'message':
            'Server URL not configured. Please set the server URL in Settings.',
      };
    }

    try {
      final baseUri = Uri.parse(serverUrl.trim());
      final host = baseUri.host;
      final port = baseUri.hasPort
          ? baseUri.port
          : (baseUri.scheme == 'https' || baseUri.scheme == 'wss' ? 443 : 80);
      final scheme = (baseUri.scheme == 'https' || baseUri.scheme == 'wss')
          ? 'https'
          : 'http';
      final loginUrl = '$scheme://$host:$port/api/v1/auth/login';

      final deviceId = await NativeService.instance.getDeviceId();

      final response = await _dio.post(
        loginUrl,
        data: {
          'identifier': identifier.trim(),
          'password': password,
          'device_id': deviceId,
        },
        options: Options(
          sendTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
          validateStatus: (status) => status != null && status < 500,
        ),
      );

      final data = response.data is Map
          ? response.data
          : jsonDecode(response.data.toString());

      if (response.statusCode == 200 && data['success'] == true) {
        final userMap = data['user'] as Map<String, dynamic>? ?? {};
        final serverId = userMap['id'] as int?;
        final token = data['token'] as String? ?? '';
        final role = userMap['role'] as String? ?? 'user';
        final status = userMap['status'] as String? ?? 'active';
        final deviceStatus = userMap['device_status'] as String? ?? 'active';

        final permsRaw = userMap['permissions'];
        List<String> perms = [];
        if (permsRaw is List) {
          perms = permsRaw.map((e) => e.toString()).toList();
        } else if (permsRaw is String) {
          perms = permsRaw.split(',').map((e) => e.trim()).toList();
        }

        final user = UserModel(
          serverUserId: serverId,
          username: userMap['username'] as String? ?? identifier,
          mobile: userMap['mobile'] as String? ?? '',
          email: userMap['email'] as String? ?? '',
          authToken: token,
          role: role,
          permissions: perms,
          status: status,
          deviceStatus: deviceStatus,
          isGuest: false,
          isActive: true,
          createdAt: DateTime.now().millisecondsSinceEpoch,
        );

        await _userDao.saveUser(user);
        _currentUser = user;
        _userPermsController.add(user);

        // Automatically bind login identifier
        if (identifier.contains('@')) {
          await addBinding(type: 'email', value: identifier);
        } else {
          await addBinding(type: 'mobile', value: identifier);
        }

        return {
          'success': true,
          'message':
              'Welcome back, ${user.username}! (Role: ${user.role.toUpperCase()})',
        };
      } else if (response.statusCode == 403) {
        return {
          'success': false,
          'message':
              data['message'] ?? 'Access denied. Account or device is blocked.',
        };
      } else if (response.statusCode == 401) {
        return {
          'success': false,
          'message': data['message'] ?? 'Invalid username or password.',
        };
      } else {
        return {
          'success': false,
          'message':
              data['message'] ??
              'Server error (${response.statusCode}). Please check server logs.',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message':
            'Cannot reach authentication server: ${e.toString().replaceAll('\n', ' ')}',
      };
    }
  }

  Future<Map<String, dynamic>> validateAndRefreshUser() async {
    final user = await getCurrentUser();
    if (user.isGuest || user.authToken.isEmpty) {
      return {'success': false, 'message': 'Not logged in (Guest mode)'};
    }

    final settings = await _settingsDao.getSettings();
    final serverUrl = settings['server_url'] as String? ?? '';
    if (serverUrl.trim().isEmpty) {
      return {'success': false, 'message': 'Server URL not configured'};
    }

    try {
      final baseUri = Uri.parse(serverUrl.trim());
      final host = baseUri.host;
      final port = baseUri.hasPort
          ? baseUri.port
          : (baseUri.scheme == 'https' || baseUri.scheme == 'wss' ? 443 : 80);
      final scheme = (baseUri.scheme == 'https' || baseUri.scheme == 'wss')
          ? 'https'
          : 'http';
      final meUrl = '$scheme://$host:$port/api/v1/auth/me';

      final deviceId = await NativeService.instance.getDeviceId();

      final response = await _dio.get(
        meUrl,
        options: Options(
          sendTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
          headers: {
            'Authorization': 'Bearer ${user.authToken}',
            'X-Device-Id': deviceId,
          },
          validateStatus: (status) => status != null && status < 500,
        ),
      );

      final data = response.data is Map
          ? response.data
          : jsonDecode(response.data.toString());

      if (response.statusCode == 200 && data['success'] == true) {
        final u = data['user'] as Map<String, dynamic>? ?? {};
        final permsRaw = u['permissions'];
        List<String> perms = [];
        if (permsRaw is List) {
          perms = permsRaw.map((e) => e.toString()).toList();
        } else if (permsRaw is String) {
          perms = permsRaw.split(',').map((e) => e.trim()).toList();
        }

        final updated = user.copyWith(
          username: u['username'] as String?,
          role: u['role'] as String?,
          status: u['status'] as String?,
          deviceStatus: u['device_status'] as String?,
          permissions: perms,
          mobile: u['mobile'] as String?,
          email: u['email'] as String?,
        );

        await _userDao.saveUser(updated);
        _currentUser = updated;
        _userPermsController.add(updated);

        return {
          'success': true,
          'message':
              'Account validation successful! Role: ${updated.role.toUpperCase()}',
          'user': updated,
        };
      } else if (response.statusCode == 403) {
        final updated = user.copyWith(status: 'blocked');
        await _userDao.saveUser(updated);
        _currentUser = updated;
        _userPermsController.add(updated);
        return {
          'success': false,
          'message':
              data['message'] ??
              'Account or device has been blocked by administrator.',
          'user': updated,
        };
      } else if (response.statusCode == 401) {
        // Session expired or revoked on server
        await logout();
        return {
          'success': false,
          'message': 'Session expired or revoked by administrator. Please log in again.',
        };
      } else {
        return {
          'success': false,
          'message':
              'Validation failed (${response.statusCode}): ${data['message'] ?? ''}',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Failed to reach server for validation: $e',
      };
    }
  }

  Future<void> logout() async {
    final user = await getCurrentUser();
    if (!user.isGuest && user.authToken.isNotEmpty) {
      try {
        final settings = await _settingsDao.getSettings();
        final serverUrl = settings['server_url'] as String? ?? '';
        if (serverUrl.trim().isNotEmpty) {
          final baseUri = Uri.parse(serverUrl.trim());
          final host = baseUri.host;
          final port = baseUri.hasPort
              ? baseUri.port
              : (baseUri.scheme == 'https' || baseUri.scheme == 'wss'
                    ? 443
                    : 80);
          final scheme = (baseUri.scheme == 'https' || baseUri.scheme == 'wss')
              ? 'https'
              : 'http';
          final logoutUrl = '$scheme://$host:$port/api/v1/auth/logout';

          await _dio.post(
            logoutUrl,
            options: Options(
              headers: {'Authorization': 'Bearer ${user.authToken}'},
              sendTimeout: const Duration(seconds: 5),
              receiveTimeout: const Duration(seconds: 5),
            ),
          );
        }
      } catch (_) {}
    }

    await _userDao.setGuestMode();
    _currentUser = await _userDao.getActiveUser();
    _userPermsController.add(_currentUser!);
  }

  Future<void> continueAsGuest() async {
    await _userDao.setGuestMode();
    _currentUser = await _userDao.getActiveUser();
    _userPermsController.add(_currentUser!);
  }

  Future<int?> findBoundUserIdFor(String contactOrNumber) async {
    if (contactOrNumber.trim().isEmpty) {
      return await getEffectiveUserId();
    }
    final binding = await _userDao.findBindingByValue(contactOrNumber);
    if (binding != null) {
      return binding.userId;
    }
    return await getEffectiveUserId();
  }

  Future<void> addBinding({required String type, required String value}) async {
    if (value.trim().isEmpty) return;
    final user = await getCurrentUser();
    final userId = user.effectiveUserId ?? 1;

    final existing = await _userDao.findBindingByValue(value);
    if (existing != null) return;

    await _userDao.addBinding(
      UserBindingModel(
        userId: userId,
        type: type,
        value: value.trim(),
        createdAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  Future<List<UserBindingModel>> getBindings() async {
    final user = await getCurrentUser();
    final userId = user.effectiveUserId;
    if (userId == null) {
      return await _userDao.getAllBindings();
    }
    return await _userDao.getBindingsForUser(userId);
  }

  Future<void> deleteBinding(int id) async {
    await _userDao.deleteBinding(id);
  }

  Future<void> handleServerPermissionUpdate({
    String? role,
    List<String>? permissions,
    String? status,
  }) async {
    final user = await getCurrentUser();
    final updated = user.copyWith(
      role: role ?? user.role,
      permissions: permissions ?? user.permissions,
      status: status ?? user.status,
    );
    await _userDao.saveUser(updated);
    _currentUser = updated;
    _userPermsController.add(updated);
  }

  Future<String> getForwardingMode() async {
    final isFiltered = await _settingsDao.isSendFilteredOnly();
    return isFiltered ? 'filtered' : 'all';
  }

  Future<void> setForwardingMode(String mode) async {
    await _settingsDao.setSendFilteredOnly(mode == 'filtered');
    try {
      final settings = await _settingsDao.getSettings();
      final serverUrl = settings['server_url'] as String? ?? '';
      final user = await getCurrentUser();
      if (serverUrl.trim().isNotEmpty && user.authToken.isNotEmpty) {
        final baseUri = Uri.parse(serverUrl.trim());
        final scheme = (baseUri.scheme == 'https' || baseUri.scheme == 'wss')
            ? 'https'
            : 'http';
        final port = baseUri.hasPort
            ? baseUri.port
            : (scheme == 'https' ? 443 : 80);
        final putUrl =
            '$scheme://${baseUri.host}:$port/api/v1/settings/forwarding-mode';
        await _dio.put(
          putUrl,
          data: {'mode': mode},
          options: Options(
            headers: {'Authorization': 'Bearer ${user.authToken}'},
            validateStatus: (_) => true,
          ),
        );
      }
    } catch (_) {}
  }

  Future<void> deleteServerEvents({
    List<int>? ids,
    String? type,
    bool? all,
  }) async {
    try {
      final settings = await _settingsDao.getSettings();
      final serverUrl = settings['server_url'] as String? ?? '';
      final user = await getCurrentUser();
      if (serverUrl.trim().isNotEmpty && user.authToken.isNotEmpty) {
        final baseUri = Uri.parse(serverUrl.trim());
        final scheme = (baseUri.scheme == 'https' || baseUri.scheme == 'wss')
            ? 'https'
            : 'http';
        final port = baseUri.hasPort
            ? baseUri.port
            : (scheme == 'https' ? 443 : 80);
        final deleteUrl = '$scheme://${baseUri.host}:$port/api/v1/events';
        await _dio.delete(
          deleteUrl,
          data: {
            if (ids != null) 'ids': ids,
            if (type != null) 'type': type,
            if (all != null) 'all': all,
          },
          options: Options(
            headers: {'Authorization': 'Bearer ${user.authToken}'},
            validateStatus: (_) => true,
          ),
        );
      }
    } catch (_) {}
  }
}
