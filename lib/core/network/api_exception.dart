class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode, this.code});

  final String message;
  final int? statusCode;
  final String? code;

  @override
  String toString() => message;

  static ApiException fromStatus(int status, {String? code, String? bodyMessage}) {
    final mapped = switch (status) {
      400 => bodyMessage ?? 'The information entered is invalid.',
      401 => 'Your session expired. Please sign in again.',
      403 =>
        'You do not have permission to use this feature for the selected business.',
      404 => 'The requested API service could not be found.',
      405 => 'This action is not supported.',
      413 => 'The selected image or request is too large.',
      429 => 'Sabi has received too many requests. Please wait and try again.',
      502 || 503 => 'Sabi is temporarily unavailable. Please try again.',
      500 => 'Something went wrong while processing the request.',
      _ => bodyMessage ?? 'Something went wrong while processing the request.',
    };
    return ApiException(mapped, statusCode: status, code: code);
  }
}
