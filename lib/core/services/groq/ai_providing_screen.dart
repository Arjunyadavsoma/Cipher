import 'package:cipher_ai/core/services/groq/api_key_manager_screen.dart';
import 'package:flutter/material.dart';
import 'package:cipher_ai/core/services/groq/ai_pooling.dart';
import 'package:cipher_ai/core/services/groq/ai_provider.dart';

class AiProviderSettingsScreen extends StatefulWidget {
  const AiProviderSettingsScreen({super.key});

  @override
  State<AiProviderSettingsScreen> createState() =>
      _AiProviderSettingsScreenState();
}

class _AiProviderSettingsScreenState extends State<AiProviderSettingsScreen> {
  List<AiProvider> _providers = [];
  String? _selectedProviderId;
  String? _selectedModelId;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // 1. Load providers (built-ins + user overrides from Firestore).
      final providers = await ProviderPoolService.instance.getProviders();

      if (providers.isEmpty) {
        setState(() {
          _error = 'No providers available.';
          _loading = false;
        });
        return;
      }

      // 2. Load saved selection from Firestore.
      final saved = await ProviderPoolService.instance.getSelected();

      // 3. Validate the saved selection against available providers.
      String? providerId = saved?.providerId;
      String? modelId = saved?.modelId;

      // Fall back to first provider if saved one doesn't exist.
      AiProvider? selectedProvider;
      if (providerId != null) {
        selectedProvider = providers.where((p) => p.id == providerId).firstOrNull;
      }
      selectedProvider ??= providers.first;
      providerId = selectedProvider.id;

      // Fall back to first model if saved one doesn't belong to provider.
      if (modelId == null ||
          !selectedProvider.models.any((m) => m.id == modelId)) {
        modelId = selectedProvider.models.isNotEmpty
            ? selectedProvider.models.first.id
            : null;
      }

      setState(() {
        _providers = providers;
        _selectedProviderId = providerId;
        _selectedModelId = modelId;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load settings: $e';
        _loading = false;
      });
    }
  }

  AiProvider? get _selectedProvider {
    if (_selectedProviderId == null) return null;
    return _providers
        .where((p) => p.id == _selectedProviderId)
        .firstOrNull;
  }

  Future<void> _selectProvider(AiProvider provider) async {
    final firstModel =
        provider.models.isNotEmpty ? provider.models.first.id : null;

    setState(() {
      _selectedProviderId = provider.id;
      _selectedModelId = firstModel;
    });

    if (firstModel != null) {
      try {
        await ProviderPoolService.instance.setSelected(
          providerId: provider.id,
          modelId: firstModel,
        );
      } catch (_) {
        // Persist best-effort.
      }
    }
  }

  Future<void> _selectModel(String modelId) async {
    setState(() => _selectedModelId = modelId);

    final providerId = _selectedProviderId;
    if (providerId != null) {
      try {
        await ProviderPoolService.instance.setSelected(
          providerId: providerId,
          modelId: modelId,
        );
      } catch (_) {
        // Persist best-effort.
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('AI Provider & Model')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48),
              const SizedBox(height: 16),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _load,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final selectedProvider = _selectedProvider;

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Provider & Model'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // --- Provider section ---
          const Text(
            'Provider',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 8),
          ..._providers.map((provider) {
            final isSelected = provider.id == _selectedProviderId;
            final hasKey = ProviderPoolService.instance.hasApiKey(provider);
            final keyCount = ProviderPoolService.instance.getKeyCount(provider);
            

            return Card(
              color: isSelected
                  ? Theme.of(context).colorScheme.primaryContainer
                  : null,
              child: ListTile(
                title: Text(provider.name),
                subtitle: Text(
                  hasKey
                      ? '${provider.models.length} models · $keyCount key${keyCount == 1 ? "" : "s"} configured'
                      : '${provider.models.length} models · ⚠ No API key set',
                ),
                leading: Icon(
                  hasKey ? Icons.check_circle : Icons.warning,
                  color: hasKey ? Colors.green : Colors.orange,
                ),
                trailing: isSelected ? const Icon(Icons.radio_button_checked) : null,
                onTap: () => _selectProvider(provider),
              ),
            );
          }),// Add this import at the top
// import 'package:cipher_ai/core/services/groq/api_key_manager_screen.dart';

// Inside the build method -> ListView children -> right after the _providers.map(...)
const SizedBox(height: 16),
SizedBox(
  width: double.infinity,
  child: OutlinedButton.icon(
    icon: const Icon(Icons.vpn_key_outlined),
    label: const Text('Manage & Test API Keys'),
    onPressed: () {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const ApiKeyManagerScreen(),
        ),
      );
    },
  ),
),
const SizedBox(height: 24),

          // --- API key warning ---
          if (selectedProvider != null &&
              !ProviderPoolService.instance.hasApiKey(selectedProvider)) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber, color: Colors.orange),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'No API key found for ${selectedProvider.name}. '
                      'Add "${selectedProvider.apiKeyEnvVar}" to your .env file. '
                      'Multiple keys can be comma-separated.',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 24),

          // --- Model section ---
          const Text(
            'Model',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 8),
          if (selectedProvider == null)
            const Text('Select a provider first.')
          else if (selectedProvider.models.isEmpty)
            const Text('No models available for this provider.')
          else
            ...selectedProvider.models.map((model) {
              return RadioListTile<String>(
                title: Row(
                  children: [
                    Flexible(child: Text(model.label)),
                    if (model.supportsThinking) ...[
                      const SizedBox(width: 8),
                      Tooltip(
                        message: 'Supports extended reasoning',
                        child: Icon(
                          Icons.psychology_outlined,
                          size: 18,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ],
                  ],
                ),
                subtitle: Text(
                  model.id,
                  style: const TextStyle(
                      fontSize: 12, fontFamily: 'monospace'),
                ),
                value: model.id,
                groupValue: _selectedModelId,
                onChanged: (value) {
                  if (value != null) _selectModel(value);
                },
              );
            }),
        ],
      ),
    );
  }
}