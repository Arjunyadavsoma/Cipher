import '../models/onboarding_page_model.dart';

final onboardingPages = [

  const OnboardingPageModel(
    title: "Welcome to Cipher",
    subtitle:
        "Cipher is your personal AI workspace that helps you complete everyday tasks faster.",
    buttonText: "Next",
    items: [

      OnboardingItem(
        icon: "chat",
        title: "Talk with AI",
        description:
            "Chat using text, voice, images and documents with multiple intelligent agents.",
      ),

      OnboardingItem(
        icon: "folder",
        title: "Organize Everything",
        description:
            "Store conversations, files, notes and knowledge in one secure workspace.",
      ),

      OnboardingItem(
        icon: "memory",
        title: "AI That Remembers",
        description:
            "Cipher remembers previous conversations and helps across ongoing projects.",
      ),
    ],
  ),

  const OnboardingPageModel(
    title: "Built to Get Work Done",
    subtitle:
        "Powerful AI tools working together inside one application.",
    buttonText: "Next",
    items: [

      OnboardingItem(
        icon: "bolt",
        title: "Multiple AI Agents",
        description:
            "Coding, research, writing, planning and analysis agents work together.",
      ),

      OnboardingItem(
        icon: "auto",
        title: "Automate Tasks",
        description:
            "Summarize files, generate reports, search the web and automate workflows.",
      ),

      OnboardingItem(
        icon: "security",
        title: "Your Data",
        description:
            "You control your conversations, files and saved knowledge.",
      ),
    ],
  ),

  const OnboardingPageModel(
    title: "Ready to Begin?",
    subtitle:
        "Sign in to access your AI workspace, saved chats and personal knowledge.",
    buttonText: "Continue",
    items: [

      OnboardingItem(
        icon: "login",
        title: "Sign In",
        description:
            "Continue with your account to sync conversations across devices.",
      ),

      OnboardingItem(
        icon: "cloud",
        title: "Cloud Sync",
        description:
            "Everything stays securely available whenever you need it.",
      ),

      OnboardingItem(
        icon: "rocket",
        title: "Start Creating",
        description:
            "Build, learn, research and automate with AI.",
      ),
    ],
  ),
];