import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/rss_article.dart';

/// Full-screen view of a single article, opened when a
/// [RssArticleCard] is tapped.
///
/// Important honesty note: [RssArticle] only ever carries the RSS
/// feed's `<description>` summary and a `link` back to the source —
/// nothing in this feature fetches the full HTML article body. So
/// this screen is the summary presented larger/unclipped (title,
/// image, full description, source, timestamp) — it is NOT the
/// complete original article. The "Read full article" button at the
/// bottom is what actually gets the person the full text, by opening
/// `article.link` in an external browser via `url_launcher`.
///
/// If you want true in-app full-article reading later, that needs a
/// separate fetch step (crawling `article.link`'s HTML, or switching
/// feeds to ones that populate `<content:encoded>`) — a bigger change
/// than this screen, left out here rather than faked with a
/// misleadingly "complete-looking" summary.
class RssArticleDetailPage extends StatelessWidget {
  final RssArticle article;

  const RssArticleDetailPage({super.key, required this.article});

  Future<void> _openFullArticle(BuildContext context) async {
    if (article.link.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No link available for this article.')),
      );
      return;
    }

    final uri = Uri.tryParse(article.link);
    if (uri == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This article\'s link looks invalid.')),
      );
      return;
    }

    final launched = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );

    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Couldn\'t open this article.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAF9),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              backgroundColor: const Color(0xFFFAFAF9),
              foregroundColor: Colors.black,
              elevation: 0,
              pinned: true,
              title: Text(
                article.sourceName,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.black,
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (article.imageUrl != null)
                    AspectRatio(
                      aspectRatio: 16 / 9,
                      child: Image.network(
                        article.imageUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            const SizedBox.shrink(),
                        loadingBuilder: (context, child, progress) {
                          if (progress == null) return child;
                          return Container(
                            color: const Color(0xFFF2F2F0),
                          );
                        },
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          article.sourceName.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF6B6B6B),
                            letterSpacing: 0.6,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          article.title,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            color: Colors.black,
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          article.relativeTime,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF9B9B9B),
                          ),
                        ),
                        const SizedBox(height: 20),
                        if (article.description.isNotEmpty)
                          Text(
                            article.description,
                            style: const TextStyle(
                              fontSize: 16,
                              color: Color(0xFF2A2A2A),
                              height: 1.55,
                            ),
                          )
                        else
                          const Text(
                            'This feed didn\'t include a summary for '
                            'this article.',
                            style: TextStyle(
                              fontSize: 15,
                              color: Color(0xFF6B6B6B),
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        const SizedBox(height: 28),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.black,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                vertical: 14,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(24),
                              ),
                              elevation: 0,
                            ),
                            onPressed: () => _openFullArticle(context),
                            child: const Text(
                              'Read full article',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}