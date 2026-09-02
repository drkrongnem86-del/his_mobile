/// HIS Pro Mobile - API Client
/// Dio HTTP client với interceptors cho authentication và error handling

import 'package:dio/dio.dart';
import 'package:his_mobile/core/constants/app_constants.dart';

class ApiClient {
  late final Dio _dio;
  final Dio? _mockDio;

  ApiClient({Dio? mockDio}) : _mockDio = mockDio {
    _dio = Dio(
      BaseOptions(
        connectTimeout: AppConstants.connectionTimeout,
        receiveTimeout: AppConstants.receiveTimeout,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );

    // Add interceptors
    _dio.interceptors.addAll([
      _AuthInterceptor(),
      _LoggingInterceptor(),
      _ErrorInterceptor(),
    ]);
  }

  Dio get dio => _mockDio ?? _dio;

  /// Build URL for specific HIS service
  String buildUrl(HisServiceType service, String endpoint) {
    final baseUrl = service.getBaseUrl();
    return '$baseUrl$endpoint';
  }

  /// GET request
  Future<Response<T>> get<T>(
    HisServiceType service,
    String endpoint, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    final url = buildUrl(service, endpoint);
    return dio.get<T>(
      url,
      queryParameters: queryParameters,
      options: options,
    );
  }

  /// POST request
  Future<Response<T>> post<T>(
    HisServiceType service,
    String endpoint, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    final url = buildUrl(service, endpoint);
    return dio.post<T>(
      url,
      data: data,
      queryParameters: queryParameters,
      options: options,
    );
  }

  /// PUT request
  Future<Response<T>> put<T>(
    HisServiceType service,
    String endpoint, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    final url = buildUrl(service, endpoint);
    return dio.put<T>(
      url,
      data: data,
      queryParameters: queryParameters,
      options: options,
    );
  }

  /// DELETE request
  Future<Response<T>> delete<T>(
    HisServiceType service,
    String endpoint, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    final url = buildUrl(service, endpoint);
    return dio.delete<T>(
      url,
      data: data,
      queryParameters: queryParameters,
      options: options,
    );
  }

  /// Set Authorization token
  void setAuthToken(String token) {
    _dio.options.headers['Authorization'] = 'Bearer $token';
  }

  /// Clear Authorization token
  void clearAuthToken() {
    _dio.options.headers.remove('Authorization');
  }
}

/// Authentication Interceptor
class _AuthInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    // Add any auth headers here if needed
    // The token will be set from AuthBloc
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (err.response?.statusCode == 401) {
      // Token expired - emit event to refresh or logout
      // This will be handled by the AuthBloc
    }
    handler.next(err);
  }
}

/// Logging Interceptor for debugging
class _LoggingInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    print('🌐 REQUEST[${options.method}] => PATH: ${options.path}');
    print('📋 Headers: ${options.headers}');
    if (options.data != null) {
      print('📦 Body: ${options.data}');
    }
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    print('✅ RESPONSE[${response.statusCode}] => PATH: ${response.requestOptions.path}');
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    print('❌ ERROR[${err.response?.statusCode}] => PATH: ${err.requestOptions.path}');
    print('📋 Error: ${err.message}');
    handler.next(err);
  }
}

/// Error Interceptor - transforms errors
class _ErrorInterceptor extends Interceptor {
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final apiError = _transformError(err);
    handler.reject(
      DioException(
        requestOptions: err.requestOptions,
        response: err.response,
        error: apiError,
        type: err.type,
      ),
    );
  }

  ApiException _transformError(DioException err) {
    switch (err.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return ApiException(
          code: 'TIMEOUT',
          message: 'Kết nối timeout. Vui lòng kiểm tra mạng VPN.',
        );
      case DioExceptionType.connectionError:
        return ApiException(
          code: 'NO_CONNECTION',
          message: 'Không thể kết nối. Vui lòng kiểm tra VPN.',
        );
      case DioExceptionType.badResponse:
        return _handleBadResponse(err.response);
      case DioExceptionType.cancel:
        return ApiException(
          code: 'CANCELLED',
          message: 'Yêu cầu đã bị hủy.',
        );
      default:
        return ApiException(
          code: 'UNKNOWN',
          message: err.message ?? 'Lỗi không xác định.',
        );
    }
  }

  ApiException _handleBadResponse(Response? response) {
    final statusCode = response?.statusCode ?? 0;
    final data = response?.data;

    String message = 'Lỗi server';
    if (data is Map && data.containsKey('Message')) {
      message = data['Message'];
    } else if (data is Map && data.containsKey('message')) {
      message = data['message'];
    }

    switch (statusCode) {
      case 400:
        return ApiException(code: 'BAD_REQUEST', message: message);
      case 401:
        return ApiException(code: 'UNAUTHORIZED', message: 'Vui lòng đăng nhập lại.');
      case 403:
        return ApiException(code: 'FORBIDDEN', message: 'Bạn không có quyền thực hiện.');
      case 404:
        return ApiException(code: 'NOT_FOUND', message: 'Không tìm thấy dữ liệu.');
      case 500:
        return ApiException(code: 'SERVER_ERROR', message: 'Lỗi server. Vui lòng thử lại.');
      default:
        return ApiException(code: 'HTTP_$statusCode', message: message);
    }
  }
}

/// Custom API Exception
class ApiException implements Exception {
  final String code;
  final String message;

  ApiException({required this.code, required this.message});

  @override
  String toString() => 'ApiException($code): $message';
}
