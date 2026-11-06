/// Error raised by the mock API layer.
///
/// Mirrors what a real backend error envelope would carry, so the UI can show
/// [message] to the customer and branch on [code].
class MockApiException implements Exception {
  final String code;
  final String message;
  final int statusCode;

  const MockApiException(this.code, this.message, {this.statusCode = 400});

  const MockApiException.badRequest(String message) : this('BAD_REQUEST', message);

  const MockApiException.notFound(String message)
      : this('NOT_FOUND', message, statusCode: 404);

  const MockApiException.methodNotAllowed(String message)
      : this('METHOD_NOT_ALLOWED', message, statusCode: 405);

  const MockApiException.networkUnavailable(String message)
      : this('NETWORK_UNAVAILABLE', message, statusCode: 503);

  @override
  String toString() => 'MockApiException($code): $message';
}

/// Customer-facing text for any error caught in the UI or state layer.
String describeError(Object error) {
  if (error is MockApiException) return error.message;
  return error.toString();
}
