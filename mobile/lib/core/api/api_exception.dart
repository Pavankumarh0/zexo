/// Normalised API error mirroring the backend envelope:
/// `{ "error": { "code": ..., "message": ... } }`.
class ApiException implements Exception {
  const ApiException({
    required this.statusCode,
    required this.code,
    required this.message,
  });

  final int statusCode;
  final String code;
  final String message;

  bool get isUnauthorized => statusCode == 401;
  bool get isForbidden => statusCode == 403;
  bool get isConflict => statusCode == 409;
  bool get isValidation => statusCode == 422;

  factory ApiException.fromResponse(int statusCode, Object? data) {
    if (data is Map && data['error'] is Map) {
      final error = data['error'] as Map;
      return ApiException(
        statusCode: statusCode,
        code: (error['code'] ?? 'error').toString(),
        message: (error['message'] ?? 'Something went wrong').toString(),
      );
    }
    return ApiException(
      statusCode: statusCode,
      code: 'error',
      message: 'Request failed ($statusCode)',
    );
  }

  @override
  String toString() => 'ApiException($statusCode, $code): $message';
}
