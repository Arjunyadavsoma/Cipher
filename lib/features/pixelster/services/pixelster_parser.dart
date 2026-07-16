class PixelsterParser {
  static String extractPrompt(String message, String trigger) {
    final regex = RegExp(trigger, caseSensitive: false);
    return message.replaceAll(regex, '').trim();
  }
}