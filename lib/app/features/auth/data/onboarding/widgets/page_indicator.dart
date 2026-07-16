import 'package:flutter/material.dart';

class PageIndicator extends StatelessWidget {
  final int current;
  final int total;

  const PageIndicator({
    super.key,
    required this.current,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(
        total,
        (index) => AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: current == index ? 20 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: current == index
                ? Colors.black
                : Colors.grey.shade300,
            borderRadius: BorderRadius.circular(50),
          ),
        ),
      ),
    );
  }
}