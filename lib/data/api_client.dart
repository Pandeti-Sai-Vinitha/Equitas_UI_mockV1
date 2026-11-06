/// Transport used by repositories. The mock implementation dispatches in
/// process; a real one would call the backend over HTTP with the same paths
/// and `{status, data}` envelope.
abstract interface class ApiClient {
  Future<Map<String, dynamic>> get(String path);

  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body);
}
