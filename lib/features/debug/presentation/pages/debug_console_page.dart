import 'package:cipher_ai/debug_test_runner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cipher_ai/core/services/debug_logger.dart';

class DebugConsolePage extends ConsumerStatefulWidget {
  const DebugConsolePage({super.key});

  @override
  ConsumerState<DebugConsolePage> createState() => _DebugConsolePageState();
}

class _DebugConsolePageState extends ConsumerState<DebugConsolePage> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    DebugLogger.instance.addListener(_scrollToBottom);
  }

  @override
  void dispose() {
    DebugLogger.instance.removeListener(_scrollToBottom);
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final logger = DebugLogger.instance;

    return Scaffold(
      appBar: AppBar(
        title: const Text("System Logs"),
        actions: [
          IconButton(
            icon: const Icon(Icons.cleaning_services_outlined),
            tooltip: "Clear Logs",
            onPressed: () => logger.clear(),
          ),
          IconButton(
            icon: const Icon(Icons.play_arrow),
            tooltip: "Run RAG Tests",
            onPressed: () => DebugTestRunner.runAllTests(),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: logger,
        builder: (context, child) {
          if (logger.logs.isEmpty) {
            return const Center(
              child: Text(
                "No logs yet.\nMake sure you are logged in, then press the Play button (▶️) in the top right to run RAG tests.",
                textAlign: TextAlign.center,
              ),
            );
          }

          return Container(
            color: Colors.black87, // Terminal background
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(12),
              itemCount: logger.logs.length,
              itemBuilder: (context, index) {
                final log = logger.logs[index];

                // Color code based on log content
                Color textColor = Colors.white70; // Default text
                if (log.contains('❌') || log.contains('ERROR') || log.contains('Error:') || log.contains('🔥')) {
                  textColor = Colors.redAccent;
                } else if (log.contains('⚠️') || log.contains('W/')) {
                  textColor = Colors.orangeAccent;
                } else if (log.contains('✅')) {
                  textColor = Colors.lightGreenAccent;
                } else if (log.contains('🚀') || log.contains('🏁')) {
                  textColor = Colors.cyanAccent;
                } else if (log.contains('I/flutter')) {
                  textColor = Colors.white54;
                }

                return Text(
                  log,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    color: textColor,
                    fontSize: 12,
                    height: 1.4,
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}