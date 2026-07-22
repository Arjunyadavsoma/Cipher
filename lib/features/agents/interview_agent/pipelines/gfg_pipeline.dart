import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as parser;

class GFGPipeline {
  final String companyId; // e.g., "google"

  GFGPipeline(this.companyId);

  /// Executes the pipeline and returns a list of extracted questions
  Future<List<Map<String, dynamic>>> execute() async {
    try {
      final url = 'https://www.geeksforgeeks.org/company/$companyId/';
      final response = await http.get(Uri.parse(url));

      if (response.statusCode != 200) {
        print('GFG Pipeline: Failed to fetch $url');
        return [];
      }

      // Parse the HTML document
      final document = parser.parse(response.body);
      
      // GFG usually stores articles in elements with class 'article-item' or similar.
      // Note: GFG frequently updates their DOM. You may need to update this selector.
      // We are looking for the titles of the problems.
      final questionElements = document.querySelectorAll('.article-item .content a, .post-list a');

      List<Map<String, dynamic>> extractedQuestions = [];
      
      for (var element in questionElements) {
        String title = element.text.trim();
        
        // Filter out empty strings or navigation links
        if (title.isNotEmpty && title.length > 10 && !title.contains('GeeksforGeeks')) {
          extractedQuestions.add({
            'title': title,
            'topic': _guessTopic(title), // Basic heuristic
            'difficulty': 'Medium', // GFG doesn't show difficulty in the list view easily
          });
        }
      }

      return extractedQuestions;
    } catch (e) {
      print('GFG Pipeline Error: $e');
      return [];
    }
  }

  // A simple heuristic to guess the topic based on the title
  String _guessTopic(String title) {
    String lowerTitle = title.toLowerCase();
    if (lowerTitle.contains('graph')) return 'Graphs';
    if (lowerTitle.contains('tree')) return 'Trees';
    if (lowerTitle.contains('array')) return 'Arrays';
    if (lowerTitle.contains('string')) return 'Strings';
    if (lowerTitle.contains('dp') || lowerTitle.contains('dynamic programming')) return 'DP';
    return 'Miscellaneous';
  }
}