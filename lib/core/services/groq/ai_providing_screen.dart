import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    // 1. Load built-in providers directly
    _providers = builtInProviders;

    // 2. Load selection from SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    final savedProviderId = prefs.getString('ai_provider_id');
    final savedModelId = prefs.getString('ai_model_id');

    // Fall back to the first built-in provider's first model if nothing
    // has been explicitly selected yet.
    final fallbackProvider = _providers.first;
    final fallbackModel = fallbackProvider.models.first;

    setState(() {
      _selectedProviderId = savedProviderId ?? fallbackProvider.id;
      
      // Ensure the saved model actually belongs to the saved provider
      AiProvider? currentProvider = _providers.firstWhere(
        (p) => p.id == _selectedProviderId,
        orElse: () => fallbackProvider,
      );
      
      bool modelExists = currentProvider.models.any((m) => m.id == savedModelId);
      _selectedModelId = (savedModelId != null && modelExists) 
          ? savedModelId 
          : fallbackModel.id;
          
      _loading = false;
    });
  }

  AiProvider? get _selectedProvider {
    if (_selectedProviderId == null) return null;
    for (final p in _providers) {
      if (p.id == _selectedProviderId) return p;
    }
    return null;
  }

  Future<void> _selectProvider(AiProvider provider) async {
    // Switching provider resets the model choice to that provider's
    // first model.
    final firstModel = provider.models.isNotEmpty
        ? provider.models.first.id
        : null;
        
    setState(() {
      _selectedProviderId = provider.id;
      _selectedModelId = firstModel;
    });
    
    if (firstModel != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('ai_provider_id', provider.id);
      await prefs.setString('ai_model_id', firstModel);
    }
  }

  Future<void> _selectModel(String modelId) async {
    setState(() => _selectedModelId = modelId);
    
    final providerId = _selectedProviderId;
    if (providerId != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('ai_provider_id', providerId);
      await prefs.setString('ai_model_id', modelId);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Provider & Model'),
        // Removed the "Add Provider" action button
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Provider',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 8),
          ..._providers.map((provider) {
            // We assume hasApiKey is still accessible or we just show models available.
            // If hasApiKey relies on the old service, we can just omit the subtitle or simplify it.
            final isSelected = provider.id == _selectedProviderId;
            return Card(
              color: isSelected
                  ? Theme.of(context).colorScheme.primaryContainer
                  : null,
              child: ListTile(
                title: Text(provider.name),
                subtitle: Text(
                  '${provider.models.length} models available',
                ),
                trailing: isSelected
                    ? const Icon(Icons.check_circle)
                    : null, // Removed delete button for built-ins
                onTap: () => _selectProvider(provider),
              ),
            );
          }),
          const SizedBox(height: 24),
          const Text(
            'Model',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 8),
          if (_selectedProvider == null)
            const Text('Select a provider first.')
          else
            ..._selectedProvider!.models.map((model) {
              final isSelected = model.id == _selectedModelId;
              return RadioListTile<String>(
                title: Text(model.label),
                subtitle: Text(
                  model.id,
                  style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                ),
                secondary: model.supportsThinking
                    ? const Tooltip(
                        message: 'Supports extended reasoning',
                        child: Icon(Icons.psychology_outlined),
                      )
                    : null,
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