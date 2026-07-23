import 'package:flutter/material.dart';
import 'package:cipher_ai/core/services/groq/ai_pooling.dart';
import 'package:cipher_ai/core/services/groq/ai_provider.dart';

class ApiKeyManagerScreen extends StatefulWidget {
  const ApiKeyManagerScreen({super.key});

  @override
  State<ApiKeyManagerScreen> createState() => _ApiKeyManagerScreenState();
}

class _ApiKeyManagerScreenState extends State<ApiKeyManagerScreen> {
  bool _isLoading = true;
  bool _isTesting = false;
  List<AiProvider> _providers = [];
  final Map<String, List<String>> _providerKeys = {};
  final Map<String, KeyTestStatus> _keyStatuses = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      _providers = await ProviderPoolService.instance.getProviders();
      _providerKeys.clear();
      _keyStatuses.clear();

      for (final p in _providers) {
        final keys = await ProviderPoolService.instance.getRawKeysForUi(p);
        _providerKeys[p.id] = keys;
        for (final k in keys) {
          _keyStatuses['${p.id}_$k'] = KeyTestStatus.untested;
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading keys: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _testAllKeys() async {
    setState(() => _isTesting = true);

    for (final provider in _providers) {
      final keys = _providerKeys[provider.id] ?? [];
      if (keys.isEmpty || provider.models.isEmpty) continue;

      // Use the first available model for testing
      final testModel = provider.models.first;

      for (final key in keys) {
        final statusKey = '${provider.id}_$key';
        setState(() {
          _keyStatuses[statusKey] = KeyTestStatus.testing;
        });

        final result = await ProviderPoolService.instance.testKey(
          provider,
          testModel,
          key,
        );

        setState(() {
          _keyStatuses[statusKey] = result;
        });

        // Small delay to avoid hammering APIs
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }

    setState(() => _isTesting = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Finished testing all keys.')),
      );
    }
  }

  Color _getStatusColor(KeyTestStatus status) {
    switch (status) {
      case KeyTestStatus.working:
        return Colors.green;
      case KeyTestStatus.suspended:
        return Colors.orange;
      case KeyTestStatus.deleted:
        return Colors.red;
      case KeyTestStatus.testing:
        return Colors.blue;
      case KeyTestStatus.error:
        return Colors.red.shade300;
      default:
        return Colors.grey;
    }
  }

  String _getStatusText(KeyTestStatus status) {
    switch (status) {
      case KeyTestStatus.untested: return 'Untested';
      case KeyTestStatus.testing: return 'Testing...';
      case KeyTestStatus.working: return 'Working';
      case KeyTestStatus.suspended: return 'Suspended (1 Day)';
      case KeyTestStatus.deleted: return 'Permanently Deleted';
      case KeyTestStatus.error: return 'Error';
    }
  }

  String _maskKey(String key) {
    if (key.length <= 8) return key;
    return '${key.substring(0, 4)}...${key.substring(key.length - 4)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('API Key Manager'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isTesting ? null : _loadData,
            tooltip: 'Reload',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      icon: _isTesting
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.science_outlined),
                      label: Text(_isTesting ? 'Testing...' : 'Test All Keys'),
                      onPressed: _isTesting ? null : _testAllKeys,
                    ),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _providers.length,
                    itemBuilder: (context, index) {
                      final provider = _providers[index];
                      final keys = _providerKeys[provider.id] ?? [];

                      if (keys.isEmpty) return const SizedBox.shrink();

                      return Card(
                        margin: const EdgeInsets.only(bottom: 16),
                        child: Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                provider.name,
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                              ),
                              const Divider(),
                              ...keys.map((key) {
                                final statusKey = '${provider.id}_$key';
                                final status = _keyStatuses[statusKey] ?? KeyTestStatus.untested;

                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 6.0),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          _maskKey(key),
                                          style: const TextStyle(fontFamily: 'monospace'),
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: _getStatusColor(status).withOpacity(0.2),
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(
                                            color: _getStatusColor(status),
                                          ),
                                        ),
                                        child: Text(
                                          _getStatusText(status),
                                          style: TextStyle(
                                            color: _getStatusColor(status),
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}