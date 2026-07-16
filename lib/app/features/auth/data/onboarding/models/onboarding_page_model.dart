class OnboardingPageModel {
  final String title;
  final String subtitle;
  final List<OnboardingItem> items;
  final String buttonText;

  const OnboardingPageModel({
    required this.title,
    required this.subtitle,
    required this.items,
    required this.buttonText,
  });
}

class OnboardingItem {
  final String title;
  final String description;
  final String icon;

  const OnboardingItem({
    required this.title,
    required this.description,
    required this.icon,
  });
}