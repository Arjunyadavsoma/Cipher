import 'package:http/http.dart' as http;
import 'package:mimir_ai/features/agents/models/tool.dart';

/// Generic HTTP fetch for agents that need to pull raw external content
/// (e.g. GfgFetchService scraping the GeeksforGeeks Problem of the Day
/// page). Registered as 'http'.
///
/// KNOWN LIMITATION, not fixable inside this tool alone: GfgFetchService
/// already anticipates that GeeksforGeeks may return a Cloudflare
/// challenge page ("Just a moment...") instead of real content - a
/// plain http.get() can't get past that (it needs a JS-executing
/// client or a scraping proxy service). Registering this tool turns
/// that case from "Tool 'http' not registered" into the actual
/// "GeeksforGeeks is blocking the request (Cloudflare)" message
/// GfgFetchService already writes - a real, informative failure
/// instead of a fake one, but still a failure until a proper scraping
/// path is added.
class HttpTool implements Tool {
  @override
  String get name => 'http';

  static const _defaultHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/125.0 Safari/537.36',
  };

  @override
  Future<dynamic> execute(Map<String, dynamic> input) async {
    final url = input['url'] as String?;
    if (url == null || url.isEmpty) {
      throw Exception('HttpTool: "url" is required');
    }

    final method = (input['method'] as String? ?? 'GET').toUpperCase();
    final headers =
        (input['headers'] as Map?)?.cast<String, String>() ?? _defaultHeaders;
    final uri = Uri.parse(url);

    final response = method == 'POST'
        ? await http
            .post(uri, headers: headers, body: input['body'])
            .timeout(const Duration(seconds: 20))
        : await http.get(uri, headers: headers).timeout(
              const Duration(seconds: 20),
            );

    if (response.statusCode != 200) {
      throw Exception('HttpTool: HTTP ${response.statusCode} for $url');
    }

    return response.body;
  }
}