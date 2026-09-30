import 'package:dio/dio.dart';

import '../data/local/dao/settings_dao.dart';
import '../data/local/dao/otp_rule_dao.dart';
import '../domain/models/otp_rule_model.dart';
import 'auth_service.dart';

class OtpParserService {
  static final OtpParserService instance = OtpParserService._init();
  final OtpRuleDao _ruleDao = OtpRuleDao();

  List<OtpRuleModel>? _cachedRules;
  int _lastCacheTime = 0;

  OtpParserService._init();

  Future<List<OtpRuleModel>> getRules({bool forceRefresh = false}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (!forceRefresh &&
        _cachedRules != null &&
        (now - _lastCacheTime) < 30000) {
      return _cachedRules!;
    }
    _cachedRules = await _ruleDao.getEnabledRules();
    _lastCacheTime = now;
    return _cachedRules!;
  }

  Future<String?> _getBaseApiUrl() async {
    try {
      if (!await AuthService.instance.isAuthenticated()) return null;
      final settings = await SettingsDao().getSettings();
      var serverUrl = (settings['server_url'] as String? ?? '').trim();
      if (serverUrl.isEmpty) return null;

      if (serverUrl.startsWith('ws://'))
        serverUrl = serverUrl.replaceFirst('ws://', 'http://');
      if (serverUrl.startsWith('wss://'))
        serverUrl = serverUrl.replaceFirst('wss://', 'https://');
      if (!serverUrl.startsWith('http://') &&
          !serverUrl.startsWith('https://')) {
        serverUrl = 'http://$serverUrl';
      }
      final uri = Uri.parse(serverUrl);
      return '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}';
    } catch (_) {
      return null;
    }
  }

  Future<Options> _getRequestOptions() async {
    final settings = await SettingsDao().getSettings();
    final user = await AuthService.instance.getCurrentUser();
    final timeout = settings['connection_timeout'] as int? ?? 15;

    final headers = <String, dynamic>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (user.authToken.isNotEmpty) {
      headers['Authorization'] = 'Bearer ${user.authToken}';
    }

    return Options(
      headers: headers,
      sendTimeout: Duration(seconds: timeout),
      receiveTimeout: Duration(seconds: timeout),
      validateStatus: (status) => status != null && status < 500,
    );
  }

  List<OtpRuleModel> _parseRulesFromResponse(dynamic data) {
    final List<OtpRuleModel> result = [];
    if (data == null) return result;

    dynamic rawList;
    if (data is Map) {
      rawList = data['rules'] ?? data['data'];
    } else if (data is List) {
      rawList = data;
    }

    if (rawList is List) {
      for (final item in rawList) {
        if (item is Map) {
          result.add(OtpRuleModel.fromMap(Map<String, dynamic>.from(item)));
        }
      }
    }
    return result;
  }

  /// Pull all rules from the server and upsert into local SQLite
  Future<List<OtpRuleModel>> syncRulesFromServer() async {
    try {
      final base = await _getBaseApiUrl();
      if (base == null) return await _ruleDao.getAllRules();

      final options = await _getRequestOptions();
      final response = await Dio().get(
        '$base/api/v1/otp-rules',
        options: options,
      );

      if (response.statusCode != null &&
          response.statusCode! >= 200 &&
          response.statusCode! < 300) {
        final serverRules = _parseRulesFromResponse(response.data);
        for (final rule in serverRules) {
          await _ruleDao.upsertRuleFromServer(rule);
        }
        invalidateCache();
      }
    } catch (e) {
      // Network errors should not crash the app
    }
    return await _ruleDao.getAllRules();
  }

  /// Push a new rule to the server
  Future<bool> pushRuleToServer(OtpRuleModel rule) async {
    try {
      final base = await _getBaseApiUrl();
      if (base == null) return false;

      final options = await _getRequestOptions();
      final payload = rule.toServerPayload();
      final response = await Dio().post(
        '$base/api/v1/otp-rules',
        data: payload,
        options: options,
      );

      if (response.statusCode != null &&
          response.statusCode! >= 200 &&
          response.statusCode! < 300) {
        if (response.data is Map &&
            response.data['id'] != null &&
            rule.id != null) {
          final serverId = response.data['id'] as int;
          await _ruleDao.updateServerId(rule.id!, serverId);
        }
        invalidateCache();
        return true;
      }
    } catch (_) {}
    return false;
  }

  /// Update an existing rule on the server
  Future<bool> updateRuleOnServer(OtpRuleModel rule) async {
    try {
      final base = await _getBaseApiUrl();
      if (base == null) return false;

      final options = await _getRequestOptions();
      final target = rule.serverId != null
          ? '${rule.serverId}'
          : Uri.encodeComponent(rule.ruleName);
      final payload = rule.toServerPayload();
      final response = await Dio().put(
        '$base/api/v1/otp-rules/$target',
        data: payload,
        options: options,
      );

      if (response.statusCode != null &&
          response.statusCode! >= 200 &&
          response.statusCode! < 300) {
        invalidateCache();
        return true;
      }
      // If PUT fails or not supported, fallback to POST upsert
      return await pushRuleToServer(rule);
    } catch (_) {
      return false;
    }
  }

  /// Delete a rule from the server
  Future<bool> deleteRuleFromServer(OtpRuleModel rule) async {
    try {
      final base = await _getBaseApiUrl();
      if (base == null) return false;

      final options = await _getRequestOptions();
      final target = rule.serverId != null
          ? '${rule.serverId}'
          : Uri.encodeComponent(rule.ruleName);
      final response = await Dio().delete(
        '$base/api/v1/otp-rules/$target',
        options: options,
      );

      if (response.statusCode != null &&
          response.statusCode! >= 200 &&
          response.statusCode! < 300) {
        invalidateCache();
        return true;
      }
    } catch (_) {}
    return false;
  }

  /// Full 2-way bidirectional sync:
  /// 1. Pushes all local rules to server /sync endpoint
  /// 2. Server upserts and returns the master list of all rules
  /// 3. App updates all local records with the combined server state
  Future<Map<String, dynamic>> syncBidirectional() async {
    try {
      final base = await _getBaseApiUrl();
      if (base == null) {
        return {'success': false, 'message': 'Server URL is not configured.'};
      }

      final localRules = await _ruleDao.getAllRules();
      final options = await _getRequestOptions();

      // Attempt the bulk bidirectional sync endpoint first
      try {
        final syncPayload = {
          'rules': localRules.map((r) => r.toServerPayload()).toList(),
        };
        final response = await Dio().post(
          '$base/api/v1/otp-rules/sync',
          data: syncPayload,
          options: options,
        );

        if (response.statusCode != null &&
            response.statusCode! >= 200 &&
            response.statusCode! < 300) {
          final serverRules = _parseRulesFromResponse(response.data);
          for (final rule in serverRules) {
            await _ruleDao.upsertRuleFromServer(rule);
          }
          invalidateCache();
          final updatedRules = await _ruleDao.getAllRules();
          return {
            'success': true,
            'count': updatedRules.length,
            'message':
                'Successfully synced ${updatedRules.length} rules both ways with server.',
          };
        }
      } catch (_) {
        // Fallback to GET + push
      }

      // Fallback: Pull from server first, then push local rules not present
      final getResponse = await Dio().get(
        '$base/api/v1/otp-rules',
        options: options,
      );
      if (getResponse.statusCode != null &&
          getResponse.statusCode! >= 200 &&
          getResponse.statusCode! < 300) {
        final serverRules = _parseRulesFromResponse(getResponse.data);
        final serverRuleNames = serverRules
            .map((r) => r.ruleName.toLowerCase())
            .toSet();

        for (final rule in serverRules) {
          await _ruleDao.upsertRuleFromServer(rule);
        }

        // Push any local rule that isn't on the server
        for (final local in localRules) {
          if (!serverRuleNames.contains(local.ruleName.toLowerCase())) {
            await pushRuleToServer(local);
          }
        }

        invalidateCache();
        final finalRules = await _ruleDao.getAllRules();
        return {
          'success': true,
          'count': finalRules.length,
          'message': 'Synced ${finalRules.length} rules with server.',
        };
      }

      return {
        'success': false,
        'message': 'Server returned status ${getResponse.statusCode}',
      };
    } catch (e) {
      return {'success': false, 'message': 'Sync error: $e'};
    }
  }

  void invalidateCache() {
    _cachedRules = null;
    _lastCacheTime = 0;
  }

  Future<String?> parseOtp({
    required String body,
    String? sender,
    String? serviceCenter,
    String type = 'sms',
  }) async {
    if (body.trim().isEmpty) return null;

    final rules = await getRules();
    for (final rule in rules) {
      if (!rule.enabled) continue;

      // 1. Match type if specified
      if (rule.type.isNotEmpty &&
          rule.type.toLowerCase() != 'all' &&
          rule.type.toLowerCase() != type.toLowerCase()) {
        continue;
      }

      // 2. Match sender if specified in rule
      if (rule.sender != null && rule.sender!.trim().isNotEmpty) {
        final expectedSender = rule.sender!.trim().toLowerCase();
        final actualSender = (sender ?? '').trim().toLowerCase();
        if (!actualSender.contains(expectedSender) &&
            !expectedSender.contains(actualSender)) {
          continue;
        }
      }

      // 3. Match service center if specified in rule
      if (rule.serviceCenter != null && rule.serviceCenter!.trim().isNotEmpty) {
        final expectedSc = rule.serviceCenter!.replaceAll(
          RegExp(r'[^0-9]'),
          '',
        );
        final actualSc = (serviceCenter ?? '').replaceAll(
          RegExp(r'[^0-9]'),
          '',
        );
        if (expectedSc.isNotEmpty &&
            actualSc.isNotEmpty &&
            !actualSc.contains(expectedSc)) {
          continue;
        }
      }

      // 4. Match regex and extract OTP
      final extracted = evaluateRegexRule(
        regexStr: rule.regex,
        attribute: rule.attribute,
        regIndex: rule.regIndex,
        text: body,
      );

      if (extracted != null && extracted.isNotEmpty) {
        return extracted;
      }
    }

    return null;
  }

  static String? evaluateRegexRule({
    required String regexStr,
    required String attribute,
    required int regIndex,
    required String text,
  }) {
    if (regexStr.trim().isEmpty || text.trim().isEmpty) return null;

    try {
      final isCaseInsensitive = attribute.contains('i');
      final isMultiLine = attribute.contains('m');

      final regExp = RegExp(
        regexStr,
        caseSensitive: !isCaseInsensitive,
        multiLine: isMultiLine,
      );

      final match = regExp.firstMatch(text);
      if (match != null) {
        if (regIndex <= match.groupCount && match.group(regIndex) != null) {
          final otp = match.group(regIndex)!.trim();
          if (otp.isNotEmpty) return otp;
        }
        if (match.group(0) != null) {
          final fullMatch = match.group(0)!.trim();
          // Extract numbers if full match
          final numMatch = RegExp(r'\d{4,8}').firstMatch(fullMatch);
          if (numMatch != null) return numMatch.group(0);
          return fullMatch;
        }
      }
    } catch (_) {
      // Regex parsing error
    }
    return null;
  }
}
