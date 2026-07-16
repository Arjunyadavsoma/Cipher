import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/onboarding_provider.dart';
import '../widgets/onboarding_card.dart';
import '../widgets/page_indicator.dart';

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final PageController controller = PageController();

  int page = 0;

  IconData getIcon(String value) {
    switch (value) {
      case "chat":
        return Icons.chat_outlined;
      case "folder":
        return Icons.folder_copy_outlined;
      case "memory":
        return Icons.psychology_outlined;
      case "bolt":
        return Icons.auto_awesome_outlined;
      case "auto":
        return Icons.settings_suggest_outlined;
      case "security":
        return Icons.lock_outline;
      case "login":
        return Icons.login;
      case "cloud":
        return Icons.cloud_outlined;
      default:
        return Icons.rocket_launch_outlined;
    }
  }

  Future<void> _next() async {
    if (page < onboardingPages.length - 1) {
      controller.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('seen_onboarding', true);

    if (!mounted) return;

    context.go('/login');
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: controller,
                itemCount: onboardingPages.length,
                onPageChanged: (value) {
                  setState(() => page = value);
                },
                itemBuilder: (_, index) {
                  final data = onboardingPages[index];

                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          data.title,
                          style: const TextStyle(
                            fontSize: 44,
                            fontWeight: FontWeight.w800,
                            height: 1.1,
                          ),
                        ),

                        const SizedBox(height: 18),

                        Text(
                          data.subtitle,
                          style: TextStyle(
                            fontSize: 17,
                            color: Colors.grey.shade600,
                            height: 1.45,
                          ),
                        ),

                        const SizedBox(height: 42),

                        ...data.items.map(
                          (item) => Padding(
                            padding: const EdgeInsets.only(bottom: 30),
                            child: OnboardingCard(
                              icon: getIcon(item.icon),
                              title: item.title,
                              description: item.description,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: PageIndicator(
                current: page,
                total: onboardingPages.length,
              ),
            ),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: SizedBox(
                width: double.infinity,
                height: 54,
                child: FilledButton(
                  onPressed: _next,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                    shape: const StadiumBorder(),
                  ),
                  child: Text(
                    onboardingPages[page].buttonText,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 18),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                "By continuing, you agree to our Terms and Privacy Policy.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade500,
                  height: 1.4,
                ),
              ),
            ),

            const SizedBox(height: 18),
          ],
        ),
      ),
    );
  }
}