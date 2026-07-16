import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mimir_ai/app/features/rss/models/rss_source)chips.dart';
import 'package:mimir_ai/app/features/rss/view/pages/rss_provider.dart';

import '../../controller/rss_controller.dart';
import '../widgets/rss_article_card.dart';
import '../widgets/rss_empty_state.dart';

/// Main RSS feed screen: welcome title, horizontal source-suggestion
/// scroller, then the selected feed's articles below.
///
/// Visual language deliberately mirrors the chat screen
/// (`home_page.dart`) rather than introducing a new style: off-white
/// background, black text, no color accents beyond black/white/gray —
/// same restraint as the ChatGPT reference. Layout rhythm (eyebrow
/// label above a bold headline, card imagery above text) takes from
/// the Apple News+ reference.
class RssPage extends ConsumerStatefulWidget {
  final String userId;

  const RssPage({super.key, required this.userId});

  @override
  ConsumerState<RssPage> createState() => _RssPageState();
}

class _RssPageState extends ConsumerState<RssPage> {
  @override
  void initState() {
    super.initState();
    // Load sources once on mount, same explicit-init pattern as
    // HomeController rather than doing IO in build().
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(rssControllerProvider(widget.userId).notifier).loadSources();
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(rssControllerProvider(widget.userId));

    return Scaffold(
      backgroundColor: const Color(0xFFFAFAF9),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Welcome to',
                      style: TextStyle(
                        fontSize: 15,
                        color: Color(0xFF6B6B6B),
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'News Feed',
                      style: TextStyle(
                        fontSize: 32,
                        color: Colors.black,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: RssSourceChips(
                sources: controller.sources,
                selectedSource: controller.selectedSource,
                onSourceSelected: (source) {
                  ref
                      .read(rssControllerProvider(widget.userId).notifier)
                      .selectSource(source);
                },
                onAddSource: () => _showAddSourceSheet(context, ref),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 8)),
            _buildFeedSliver(controller),
          ],
        ),
      ),
    );
  }

  Widget _buildFeedSliver(RssController controller) {
    if (controller.selectedSource == null) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: RssEmptyState(
          headline: 'Pick a source to get started',
          body: 'Choose a feed above, or add your own RSS link.',
        ),
      );
    }

    switch (controller.loadState) {
      case RssLoadState.loading:
        return const SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: CircularProgressIndicator(
              color: Colors.black,
              strokeWidth: 2,
            ),
          ),
        );

      case RssLoadState.error:
        return SliverFillRemaining(
          hasScrollBody: false,
          child: RssEmptyState(
            headline: 'Couldn\'t load this feed',
            body: controller.errorMessage ?? 'Something went wrong.',
          ),
        );

      case RssLoadState.loaded:
        if (controller.articles.isEmpty) {
          return const SliverFillRemaining(
            hasScrollBody: false,
            child: RssEmptyState(
              headline: 'No articles yet',
              body: 'This feed didn\'t return any items.',
            ),
          );
        }
        return SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) =>
                  RssArticleCard(article: controller.articles[index]),
              childCount: controller.articles.length,
            ),
          ),
        );

      case RssLoadState.idle:
        return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
  }

  void _showAddSourceSheet(BuildContext context, WidgetRef ref) {
    final nameController = TextEditingController();
    final urlController = TextEditingController();

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFFFAFAF9),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Add a feed',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 16),
              _AddSourceField(label: 'Name', controller: nameController),
              const SizedBox(height: 12),
              _AddSourceField(
                label: 'Feed URL',
                controller: urlController,
                keyboardType: TextInputType.url,
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                    elevation: 0,
                  ),
                  onPressed: () {
                    if (nameController.text.trim().isEmpty ||
                        urlController.text.trim().isEmpty) {
                      return;
                    }
                    ref
                        .read(
                          rssControllerProvider(widget.userId).notifier,
                        )
                        .addCustomSource(
                          name: nameController.text.trim(),
                          feedUrl: urlController.text.trim(),
                        );
                    Navigator.of(sheetContext).pop();
                  },
                  child: const Text(
                    'Add feed',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _AddSourceField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final TextInputType? keyboardType;

  const _AddSourceField({
    required this.label,
    required this.controller,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      style: const TextStyle(color: Colors.black, fontSize: 15),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Color(0xFF6B6B6B)),
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE5E5E3)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE5E5E3)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.black, width: 1.5),
        ),
      ),
    );
  }
}