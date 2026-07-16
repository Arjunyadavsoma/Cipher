abstract class PaperProvider {
  const PaperProvider();

  /// Returns a single paper.
  Future<Map<String, String>> lookup(String query);

  /// Returns multiple related papers.
  Future<List<Map<String, String>>> search(
    String query, {
    int maxResults = 10,
  });
}

class RateLimitException implements Exception {
  final String message;

  const RateLimitException(this.message);

  @override
  String toString() => message;
}

class ProviderException implements Exception {
  final String message;

  const ProviderException(this.message);

  @override
  String toString() => message;
}