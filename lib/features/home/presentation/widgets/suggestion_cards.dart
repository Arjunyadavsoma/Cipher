import 'package:flutter/material.dart';

class SuggestionCards extends StatelessWidget {
  const SuggestionCards({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 96,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: const [
          _SuggestionCard(
            title: "Generate Image",
            subtitle: "Create visuals with AI",
          ),
          SizedBox(width: 12),
          _SuggestionCard(
            title: "Research",
            subtitle: "Summarize any topic",
          ),
          SizedBox(width: 12),
          _SuggestionCard(
            title: "Daily DSA",
            subtitle: "Solve today's question",
          ),
          SizedBox(width: 12),
          _SuggestionCard(
            title: "Automation",
            subtitle: "Create AI workflows",
          ),
        ],
      ),
    );
  }
}

class _SuggestionCard extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SuggestionCard({
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 180,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xffF7F7F8),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),

          const SizedBox(height: 6),

          Expanded(
            child: Text(
              subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                color: Colors.black54,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}