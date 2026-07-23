
/// Thrown by the AI request layer when a provider call fails. Carries the
/// HTTP status code (when available) so [ProviderPoolService.reportFailure]
/// can classify it as rate-limit vs. auth-error without string parsing.
class AiRequestException implements Exception {
  AiRequestException(
    this.message, {
    this.statusCode,
    this.responseBody,
  });

  final int? statusCode;
  final String message;
  final String? responseBody;

  @override
  String toString() => message;
}

/// A single model offered by a provider.
class AiModel {
  const AiModel({
    required this.id,
    required this.label,
    this.supportsThinking = false,
  });

  /// Exact string sent as `"model"` in the request body.
  final String id;

  /// Human-readable label shown in the picker.
  final String label;

  /// Whether this model accepts the NVIDIA-style
  /// `extra_body.chat_template_kwargs.enable_thinking` flag.
  final bool supportsThinking;

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'supportsThinking': supportsThinking,
      };

  factory AiModel.fromJson(Map<String, dynamic> json) => AiModel(
        id: json['id'] as String? ?? '',
        label: json['label'] as String? ?? json['id'] as String? ?? '',
        supportsThinking: json['supportsThinking'] as bool? ?? false,
      );
}

/// A configured AI provider: base URL, env-var name for the key(s),
/// and a list of models the user can pick from.
class AiProvider {
  AiProvider({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.apiKeyEnvVar,
    required this.models,
    this.isBuiltIn = false,
  });

  /// Stable lowercase id, e.g. `"groq"`. Used as Firestore doc-id prefix.
  final String id;
  final String name;
  final String baseUrl;
  final String apiKeyEnvVar;
  final List<AiModel> models;
  final bool isBuiltIn;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'baseUrl': baseUrl,
        'apiKeyEnvVar': apiKeyEnvVar,
        'models': models.map((m) => m.toJson()).toList(),
        'isBuiltIn': isBuiltIn,
      };

  factory AiProvider.fromJson(Map<String, dynamic> json) => AiProvider(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? 'Unknown',
        baseUrl: json['baseUrl'] as String? ?? '',
        apiKeyEnvVar: json['apiKeyEnvVar'] as String? ?? '',
        models: (json['models'] as List<dynamic>? ?? [])
            .map((m) => AiModel.fromJson(m as Map<String, dynamic>))
            .toList(),
        isBuiltIn: json['isBuiltIn'] as bool? ?? false,
      );

  AiProvider copyWith({
    String? name,
    String? baseUrl,
    String? apiKeyEnvVar,
    List<AiModel>? models,
  }) =>
      AiProvider(
        id: id,
        name: name ?? this.name,
        baseUrl: baseUrl ?? this.baseUrl,
        apiKeyEnvVar: apiKeyEnvVar ?? this.apiKeyEnvVar,
        models: models ?? this.models,
        isBuiltIn: isBuiltIn,
      );
}

/// The four built-in providers. Users can edit these (model list, etc.)
/// in Firestore; user-added providers live alongside them.
final List<AiProvider> builtInProviders = [
  AiProvider(
    id: 'groq',
    name: 'Groq',
    baseUrl: 'https://api.groq.com/openai/v1/chat/completions',
    apiKeyEnvVar: 'GROQ_API_KEY',
    isBuiltIn: true,
    models: const [
      AiModel(id: 'llama-3.3-70b-versatile', label: 'Llama 3.3 70B'),
      AiModel(id: 'moonshotai/kimi-k2-instruct', label: 'Moonshot Kimi K2'),
      AiModel(
          id: 'moonshotai/kimi-k2-instruct-0905',
          label: 'Moonshot Kimi K2 0905'),
      AiModel(
          id: 'meta-llama/llama-4-scout-17b-16e-instruct',
          label: 'Llama 4 Scout 17B'),
    ],
  ),
  AiProvider(
    id: 'modelscope',
    name: 'ModelScope',
    baseUrl: 'https://api-inference.modelscope.cn/v1/chat/completions',
    apiKeyEnvVar: 'MODELSCOPE_API_KEY',
    isBuiltIn: true,
    models: const [
      AiModel(id: 'MiniMax/MiniMax-M2.5', label: 'MiniMax M2.5 (highspeed)'),
      AiModel(id: 'qwen-qwen3-5-35b-a3b', label: 'Qwen3.5 35B A3B'),
      AiModel(id: 'qwen-qwen3-5-27b', label: 'Qwen3.5 27B'),
    ],
  ),
  AiProvider(
    id: 'cerebras',
    name: 'Cerebras',
    baseUrl: 'https://api.cerebras.ai/v1/chat/completions',
    apiKeyEnvVar: 'CEREBRAS_API_KEY',
    isBuiltIn: true,
    models: const [
      AiModel(id: 'llama3.1-70b', label: 'Llama 3.1 70B'),
      AiModel(id: 'gpt-oss-120b', label: 'GPT-OSS 120B'),
      AiModel(id: 'zai-glm-4.7', label: 'Zai GLM 4.7'),
    ],
  ),
  AiProvider(
    id: 'nvidia_nim',
    name: 'NVIDIA NIM',
    baseUrl: 'https://integrate.api.nvidia.com/v1/chat/completions',
    apiKeyEnvVar: 'NVIDIA_API_KEY',
    isBuiltIn: true,
    models: const [
      AiModel(
        id: 'z-ai/glm-5.2',
        label: 'Z-AI GLM 5.2 (reasoning)',
        supportsThinking: true,
      ),
      AiModel(id: 'z-ai/glm-5.1', label: 'Z-AI GLM 5.1'),
      AiModel(id: 'poolside/laguna-xs-2.1', label: 'Poolside Laguna XS 2.1'),
    ],
  ),
];