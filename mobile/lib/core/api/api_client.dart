import 'package:dio/dio.dart';

import '../config/app_config.dart';
import 'api_exception.dart';

/// Resolves the current bearer token (the Supabase JWT), or null if signed out.
typedef TokenProvider = String? Function();

/// Thin Dio wrapper that injects the auth header, normalises errors into
/// [ApiException], and centralises base-URL configuration.
class ApiClient {
  ApiClient({required AppConfig config, required TokenProvider tokenProvider})
      : _dio = Dio(
          BaseOptions(
            baseUrl: config.apiBaseUrl,
            connectTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 15),
            contentType: 'application/json',
          ),
        ) {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final token = tokenProvider();
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
      ),
    );
  }

  final Dio _dio;

  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    return _wrap(() => _dio.get<dynamic>(path, queryParameters: query));
  }

  Future<List<dynamic>> getList(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    final res = await _request(() => _dio.get<dynamic>(path, queryParameters: query));
    return (res.data as List<dynamic>?) ?? <dynamic>[];
  }

  Future<Map<String, dynamic>> postJson(
    String path, {
    Object? body,
  }) async {
    return _wrap(() => _dio.post<dynamic>(path, data: body));
  }

  Future<Map<String, dynamic>> putJson(
    String path, {
    Object? body,
  }) async {
    return _wrap(() => _dio.put<dynamic>(path, data: body));
  }

  Future<void> delete(String path) async {
    await _request(() => _dio.delete<dynamic>(path));
  }

  Future<Map<String, dynamic>> _wrap(
    Future<Response<dynamic>> Function() run,
  ) async {
    final res = await _request(run);
    final data = res.data;
    if (data is Map<String, dynamic>) return data;
    return <String, dynamic>{};
  }

  Future<Response<dynamic>> _request(
    Future<Response<dynamic>> Function() run,
  ) async {
    try {
      return await run();
    } on DioException catch (e) {
      final status = e.response?.statusCode ?? 0;
      if (status == 0) {
        throw ApiException(
          statusCode: 0,
          code: 'network_error',
          message: 'Network unavailable. Check your connection.',
        );
      }
      throw ApiException.fromResponse(status, e.response?.data);
    }
  }
}
