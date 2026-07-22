import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    await Future.delayed(const Duration(seconds: 2));

    if (!mounted) return;

    final prefs = await SharedPreferences.getInstance();
    final seenOnboarding = prefs.getBool('seen_onboarding') ?? false;

    if (!seenOnboarding) {
      context.go('/onboarding');
      return;
    }

    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      context.go('/login');
    } else {
      context.go('/dashboard');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
                  "assets/images/infinity_logo.png",
                  width: 120,
                  height: 120,
                )
                .animate()
                .fadeIn(duration: 800.ms)
                .scale(begin: const Offset(0.7, 0.7), duration: 800.ms),

            const SizedBox(height: 24),

            const Text(
              "cipher AI",
              style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
            ).animate().fadeIn(delay: 300.ms),

            const SizedBox(height: 30),

            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ).animate().fadeIn(delay: 700.ms),
          ],
        ),
      ),
    );
  }
}
