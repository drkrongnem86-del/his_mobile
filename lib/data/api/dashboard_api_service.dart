import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:dio/dio.dart';

/// Dashboard BV Ninh Thuận API Service
/// Base URL: http://172.16.212.213:5173/api/
class DashboardApiService {
  late final Dio _dio;
  String? _baseUrl;
  String? _sessionToken;
  Map<String, String>? _authHeader;

  // Server URL đã verify
  static const String DEFAULT_BASE = 'http://172.16.212.213:5173/api';
  static const String ALT_BASE = 'http://172.16.212.213/api';

  DashboardApiService() {
    _dio = Dio(BaseOptions(
      connectTimeout: Duration(seconds: 30),
      receiveTimeout: Duration(seconds: 30),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      validateStatus: (s) => s != null && s < 500,
    ));
  }

  /// Login với HSCC / KHOACAPCUU
  Future<LoginResult> login(String username, String password) async {
    // Try multiple base URLs
    for (final base in [DEFAULT_BASE, ALT_BASE]) {
      try {
        debugPrint('🔐 Trying login at: $base');
        
        _dio.options.baseUrl = base;
        
        final response = await _dio.post(
          '/auth/login',
          data: {
            'username': username,
            'password': password,
          },
          options: Options(
            headers: {'Content-Type': 'application/json'},
            responseType: ResponseType.json,
          ),
        );

        if (response.statusCode == 200) {
          Map<String, dynamic> data = {};
          if (response.data is Map) {
            data = Map<String, dynamic>.from(response.data);
          } else if (response.data is String) {
            try { data = jsonDecode(response.data); } catch (e) {}
          }

          if (data['success'] == true || data['token'] != null || data['user'] != null) {
            _sessionToken = data['token']?.toString();
            _baseUrl = base;
            if (_sessionToken != null) {
              _authHeader = {'Authorization': 'Bearer $_sessionToken'};
            }
            return LoginResult(success: true, data: data);
          }
          return LoginResult(success: false, message: data['message']?.toString() ?? 'Sai tài khoản');
        } else if (response.statusCode == 401 || response.statusCode == 404) {
          // Try next base URL
          debugPrint('   ❌ $base: ${response.statusCode}');
          continue;
        }
        return LoginResult(success: false, message: 'HTTP ${response.statusCode}');
      } catch (e) {
        debugPrint('   ❌ $base: ${e.toString().substring(0, e.toString().length.clamp(0, 80))}');
        continue;
      }
    }
    return LoginResult(success: false, message: 'Không kết nối được server');
  }

  /// Test connection
  Future<bool> testConnection() async {
    for (final base in [DEFAULT_BASE, ALT_BASE]) {
      try {
        final resp = await _dio.get(
          base.replaceAll('/api', '') + '/',
          options: Options(receiveTimeout: Duration(seconds: 5)),
        );
        if (resp.statusCode != null) {
          _baseUrl = base;
          return true;
        }
      } catch (e) {
        continue;
      }
    }
    return false;
  }

  /// Tìm bệnh nhân
  Future<HisResult> searchPatients(String keyword) async {
    return _get('/search-patient', {'keyword': keyword, 'limit': 50});
  }

  /// Lấy danh sách BN cấp cứu
  Future<HisResult> getEmergencyPatients({String? deptCode, int? limit}) async {
    return _get('/emergency-patients', {
      if (deptCode != null) 'department_code': deptCode,
      if (limit != null) 'limit': limit,
    });
  }

  /// Lấy BN theo khoa
  Future<HisResult> getDepartmentPatients({String? deptCode, String? deptId, int? limit}) async {
    return _get('/department-patients', {
      if (deptCode != null) 'department_code': deptCode,
      if (deptId != null) 'department_id': deptId,
      if (limit != null) 'limit': limit,
    });
  }

  /// Thông tin lâm sàng
  Future<HisResult> getClinicalInfo(String patientId) async {
    return _get('/clinical-info', {'patient_id': patientId});
  }

  /// BN nặng
  Future<HisResult> getCriticalPatients({int? limit}) async {
    return _get('/his/critical-patient', {if (limit != null) 'limit': limit});
  }

  /// Thông tin dashboard khoa
  Future<HisResult> getDepartmentStats({String? deptCode}) async {
    return _get('/department-stats', {
      if (deptCode != null) 'department_code': deptCode,
    });
  }

  /// Sơ đồ giường khoa
  Future<HisResult> getBedMap({String? deptCode}) async {
    return _get('/his/dept-bed-map', {
      if (deptCode != null) 'department_code': deptCode,
    });
  }

  /// Dashboard tổng
  Future<HisResult> getDashboard() async {
    return _get('/dashboard', {});
  }

  /// Helper
  Future<HisResult> _get(String path, Map<String, dynamic> params) async {
    try {
      if (_baseUrl == null) {
        await testConnection();
      }
      if (_baseUrl == null) {
        return HisResult(success: false, message: 'Chưa kết nối server');
      }

      debugPrint('📡 GET $_baseUrl/$path');
      final response = await _dio.get(
        '$_baseUrl/$path',
        queryParameters: params,
        options: Options(
          headers: _authHeader ?? {},
          receiveTimeout: Duration(seconds: 30),
        ),
      );

      if (response.statusCode == 200) {
        return HisResult(success: true, data: response.data);
      }
      return HisResult(success: false, message: 'HTTP ${response.statusCode}', data: response.data);
    } catch (e) {
      return HisResult(success: false, message: e.toString().substring(0, e.toString().length.clamp(0, 100)));
    }
  }
}

class LoginResult {
  final bool success;
  final Map<String, dynamic>? data;
  final String? message;
  LoginResult({required this.success, this.data, this.message});
}

class HisResult {
  final bool success;
  final dynamic data;
  final String? message;
  HisResult({required this.success, this.data, this.message});
}
