import 'package:html/parser.dart' as html_parser;

class HtmlCleaner {
  /// Extracts readable text from raw HTML.
  static String extractMainContent(String rawHtml) {
    final document = html_parser.parse(rawHtml);

    // Remove unwanted tags completely
    final unwantedSelectors = ['script', 'style', 'header', 'footer', 'nav', 'aside', 'form', 'iframe'];
    for (final selector in unwantedSelectors) {
      document.querySelectorAll(selector).forEach((el) => el.remove());
    }

    // Try to find the main article tag, otherwise fall back to body
    final article = document.querySelector('article') ?? document.querySelector('main') ?? document.body;
    
    if (article == null) return '';
    
    // FIX: Changed .innerText to .text (which is the correct getter for the html package)
    final text = article.text.trim();
    
    // Clean up excessive whitespace
    return text.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  }
}