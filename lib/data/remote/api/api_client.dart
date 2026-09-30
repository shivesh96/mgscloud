import 'dart:convert';
import 'package:dio/dio.dart';
import '../../local/dao/settings_dao.dart';

class ApiClient {
  final Dio _dio;
  final SettingsDao _settingsDao;

  ApiClient(this._settingsDao) : _dio = Dio() {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final settings = await _settingsDao.getSettings();
          final url = settings['server_url'] as String? ?? '';
          final authType = settings['auth_type'] as String? ?? 'NONE';
          final authToken = settings['auth_token'] as String? ?? '';
          final timeout = settings['connection_timeout'] as int? ?? 30;
          
          if (url.isNotEmpty) {
            options.baseUrl = url;
          }
          options.connectTimeout = Duration(seconds: timeout);
          options.receiveTimeout = Duration(seconds: timeout);

          if (authType == 'BEARER' && authToken.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $authToken';
          } else if (authType == 'API_KEY' && authToken.isNotEmpty) {
            options.headers['X-Api-Key'] = authToken;
          } else if (authType == 'BASIC' && authToken.isNotEmpty) {
            options.headers['Authorization'] = 'Basic ${base64Encode(utf8.encode(authToken))}';
          }
          return handler.next(options);
        },
      ),
    );
  }

  Dio get client => _dio;
}
