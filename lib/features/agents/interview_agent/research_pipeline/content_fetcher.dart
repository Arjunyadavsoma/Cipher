import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as parser;

class ContentFetcher {
  /// Fetches URL and returns cleaned text
  Future<String> fetchAndClean(String url) async {
    try {
      final response = await http
          .get(
            Uri.parse(url),
            headers: {
              'User-Agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
            },
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) return '';

      final document = parser.parse(response.body);
      document
          .querySelectorAll('script, style, nav, footer, header')
          .forEach((el) => el.remove());

      // 1. Extract Image URLs from the page
      List<String> imageUrls = [];
      document.querySelectorAll('img').forEach((img) {
        String? src = img.attributes['src'];
        // Only keep absolute URLs and ignore tiny icons/logos
        if (src != null &&
            src.startsWith('http') &&
            !src.contains('.svg') &&
            !src.contains('logo')) {
          imageUrls.add(src);
        }
      });

      String text = document.body?.text ?? '';
      text = text.replaceAll(RegExp(r'\s+'), ' ').trim();

      // 2. Append image URLs to the text so the LLM can see them
      if (imageUrls.isNotEmpty) {
        text += "\n\n[ASSOCIATED IMAGES ON PAGE]:\n";
        text += imageUrls
            .take(5)
            .join('\n'); // Limit to 5 images to save tokens
      }

      if (text.length > 3000) {
        text = text.substring(0, 3000);
      }

      return text;
    } catch (e) {
      print('ContentFetcher skipped $url (timeout or error)');
      return '';
    }
  }
}
