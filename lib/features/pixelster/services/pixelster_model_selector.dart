class PixelsterModelSelector {
  // Pixelster uses aspect ratios instead of model IDs
  static String getAspectRatio(String prompt) {
    if (prompt.contains("tiktok") || prompt.contains("portrait")) {
      return "9:16";
    } else if (prompt.contains("youtube") || prompt.contains("cinematic")) {
      return "16:9";
    }
    return "1:1"; // Default to Square
  }
}