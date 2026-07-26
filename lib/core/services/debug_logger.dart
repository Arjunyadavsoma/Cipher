import 'package:flutter/material.dart';

class DebugLogger extends ChangeNotifier {
  DebugLogger._internal();
  static final DebugLogger instance = DebugLogger._internal();

  final List<String> _logs = [];
  List<String> get logs => List.unmodifiable(_logs);

  // Keep memory under control by capping at 1000 lines
  static const int _maxLogs = 1000;

  void log(String message) {
    final timestamp = DateTime.now().toIso8601String().substring(11, 19);
    _logs.add("[$timestamp] $message");
    
    // Remove oldest logs if we exceed the limit
    if (_logs.length > _maxLogs) {
      _logs.removeAt(0);
    }
    
    notifyListeners();
  }

  void clear() {
    _logs.clear();
    notifyListeners();
  }
}