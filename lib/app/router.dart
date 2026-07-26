import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cipher_ai/Knowledge/knowledge_Screen/knowledge_page.dart';

import 'package:cipher_ai/app/features/auth/data/onboarding/screens/onboarding_page.dart';
import 'package:cipher_ai/features/auth/presentation/forgot_password/check_email_page.dart';
import 'package:cipher_ai/features/auth/presentation/forgot_password/forgot_password_page.dart';

// NEW: Correct import for the Debug Console UI
import 'package:cipher_ai/features/debug/presentation/pages/debug_console_page.dart';

import '../../features/auth/screens/login_page.dart';
import '../../features/auth/screens/signup_page.dart';
import '../../features/auth/screens/splash_page.dart';
import '../../features/home/presentation/pages/home_page.dart';

// 1. Define the navigator key globally so main.dart and the router can share it
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

final routerProvider = Provider<GoRouter>((ref) {
  final auth = FirebaseAuth.instance;

  return GoRouter(
    navigatorKey: rootNavigatorKey, // 2. Use the global key here
    initialLocation: "/",
    refreshListenable: GoRouterRefreshStream(auth.authStateChanges()),

    redirect: (context, state) {
      final user = auth.currentUser;
      final location = state.matchedLocation;

      // Always allow Splash
      if (location == "/") {
        return null;
      }

      // Routes that DO NOT require authentication
      const publicPages = {
        "/login",
        "/signup",
        "/forgot-password",
        "/onboarding",
      };

      final isPublicPage = publicPages.contains(location);

      // User is NOT logged in
      if (user == null) {
        if (isPublicPage) {
          return null;
        }

        return "/login";
      }

      // User IS logged in
      if (isPublicPage) {
        return "/dashboard";
      }

      return null;
    },

    routes: [
      GoRoute(path: "/", builder: (_, __) => const SplashPage()),
      GoRoute(path: "/knowledge", builder: (_, __) => const KnowledgePage()),
      GoRoute(path: "/onboarding", builder: (_, __) => const OnboardingPage()),
      GoRoute(path: "/login", builder: (_, __) => const LoginPage()),
      GoRoute(path: "/signup", builder: (_, __) => const SignupPage()),
      GoRoute(
        path: "/forgot-password",
        builder: (context, state) => const ForgotPasswordPage(),
      ),
      GoRoute(
        path: "/check-email",
        builder: (context, state) {
          final email = state.extra as String;
          return CheckEmailPage(email: email);
        },
      ),
      GoRoute(path: "/dashboard", builder: (_, __) => const HomePage()),
      
      // ADDED: Debug Console Route
      GoRoute(path: "/debug", builder: (_, __) => const DebugConsolePage()),

      // 3. ADDED: Deep link route for chat notifications
      GoRoute(
        path: '/chat/:chatId',
        builder: (context, state) {
          final chatId = state.pathParameters['chatId']!;
          return HomePage(initialChatId: chatId); 
        },
      ),
    ],
  );
});

class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<dynamic> stream) {
    _subscription = stream.asBroadcastStream().listen((_) {
      notifyListeners();
    });
  }

  late final StreamSubscription<dynamic> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}