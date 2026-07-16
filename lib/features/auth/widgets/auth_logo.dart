import 'package:flutter/material.dart';

class AuthLogo extends StatelessWidget {
  const AuthLogo({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Image.asset(
          "assets/images/infinity_logo.png",
          width: 56,
          height: 56,
          fit: BoxFit.contain,
        ),
      ],
    );
  }
}