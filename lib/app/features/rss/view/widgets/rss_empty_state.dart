import 'package:flutter/material.dart';

/// Plain centered text state — used for "pick a source", load
/// errors, and "no articles". Deliberately has no illustration or
/// icon: matches the ChatGPT reference's restraint (no decoration
/// beyond black text on the off-white background).
class RssEmptyState extends StatelessWidget {
  final String headline;
  final String body;

  const RssEmptyState({
    super.key,
    required this.headline,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              headline,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              body,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF6B6B6B),
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}