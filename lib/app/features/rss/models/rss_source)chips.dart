import 'package:flutter/material.dart';
import 'package:cipher_ai/app/features/rss/models/rss_feed_source.dart';

/// Horizontal scroller of feed-source chips, sitting directly below
/// the welcome title — this is the "suggestion cards" surface
/// referenced by `suggestion_cards.dart` on the chat empty state, but
/// specific to RSS sources rather than chat prompts.
///
/// Chip style takes from the ChatGPT reference: rounded pill shape,
/// black on selection, thin gray border when unselected, no color
/// accents.
class RssSourceChips extends StatelessWidget {
  final List<RssFeedSource> sources;
  final RssFeedSource? selectedSource;
  final ValueChanged<RssFeedSource> onSourceSelected;
  final VoidCallback onAddSource;

  const RssSourceChips({
    super.key,
    required this.sources,
    required this.selectedSource,
    required this.onSourceSelected,
    required this.onAddSource,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: sources.length + 1, // +1 for the trailing "add" chip
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          if (index == sources.length) {
            return _AddChip(onTap: onAddSource);
          }
          final source = sources[index];
          final isSelected = selectedSource?.id == source.id;
          return _SourceChip(
            source: source,
            isSelected: isSelected,
            onTap: () => onSourceSelected(source),
          );
        },
      ),
    );
  }
}

class _SourceChip extends StatelessWidget {
  final RssFeedSource source;
  final bool isSelected;
  final VoidCallback onTap;

  const _SourceChip({
    required this.source,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? Colors.black : Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: isSelected ? Colors.black : const Color(0xFFE5E5E3),
            width: 1,
          ),
        ),
        child: Text(
          source.name,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.black,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _AddChip extends StatelessWidget {
  final VoidCallback onTap;

  const _AddChip({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFFE5E5E3), width: 1),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add, size: 16, color: Colors.black),
            SizedBox(width: 4),
            Text(
              'Add feed',
              style: TextStyle(
                color: Colors.black,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
