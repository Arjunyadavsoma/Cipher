/// A configured AI provider: a base URL plus one or more API keys and a
/// list of models the user can pick from. Everything here is assumed to
/// speak the OpenAI-compatible `/chat/completions` shape (same as the
/// existing ChatService._callGroq), since that's what Groq, ModelScope,
/// Cerebras, and NVIDIA NIM all expose.
///
/// NOTE ON NVIDIA NIM: its /v1/chat/completions endpoint additionally
/// supports vendor-specific fields under `extra_body` (e.g.
/// `chat_template_kwargs.enable_thinking` for reasoning-capable models
/// like z-ai/glm-5.2 - see the snippet the user pasted). This model
/// doesn't special-case that; it just stores `supportsThinking` as a
/// per-model flag so the calling code can decide whether to send that
/// extra field. Everything else about the request/response shape is
/// identical across providers here, so no per-provider request builder
/// is needed yet - if a future provider deviates (different auth header
/// name, non-OpenAI response shape, etc.) that's the point to add an
/// enum/strategy rather than bolting on more optional fields.
class AiModel {
  const AiModel({
    required this.id,
    required this.label,
    this.supportsThinking = false,
  });

  /// The exact string sent as "model" in the request body, e.g.
  /// "llama-3.3-70b-versatile" or "z-ai/glm-5.2".
  final String id;

  /// Human-readable name shown in the picker, e.g. "Llama 3.3 70B".
  final String label;

  /// Whether this model accepts the NVIDIA-style
  /// extra_body.chat_template_kwargs.enable_thinking flag. False for
  /// everything except reasoning-capable NIM models.
  final bool supportsThinking;

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'supportsThinking': supportsThinking,
      };

  factory AiModel.fromJson(Map<String, dynamic> json) => AiModel(
        id: json['id'] as String,
        label: json['label'] as String,
        supportsThinking: json['supportsThinking'] as bool? ?? false,
      );
}

class AiProvider {
  AiProvider({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.apiKeyEnvVar,
    required this.models,
    this.isBuiltIn = false,
  });

  /// Stable internal id, e.g. "groq", "modelscope". Used as the Firestore
  /// document-id prefix and as the key into .env, so keep it
  /// lowercase/no-spaces once set - renaming it orphans any stored usage
  /// counters and cooldowns the same way changing a key's suffix would
  /// (see ApiKeyPoolService._keyId's note on this).
  final String id;

  /// Display name shown in the settings screen, e.g. "Groq".
  final String name;

  /// Full chat-completions URL, e.g.
  /// "https://api.groq.com/openai/v1/chat/completions". Stored as the
  /// complete endpoint (not just the host) so providers with
  /// non-standard paths - like Cloudflare Workers AI's
  /// /accounts/{id}/ai/run or NVIDIA's /v1/chat/completions vs. the
  /// bare /v1 root other providers use - don't need special-casing
  /// later.
  final String baseUrl;

  /// Name of the .env variable holding this provider's key, e.g.
  /// "GROQ_API_KEY". Kept as a variable *name* rather than the key
  /// value itself so the key never has to be duplicated between .env
  /// and whatever persists provider configs (see ProviderPoolService).
  final String apiKeyEnvVar;

  final List<AiModel> models;

  /// True for the four providers shipped with the app (Groq, ModelScope,
  /// Cerebras, NVIDIA NIM). Built-ins can't be deleted from the settings
  /// screen, only have their key/model selection edited, so a bad edit
  /// can't accidentally remove the app's only known-working providers.
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
        id: json['id'] as String,
        name: json['name'] as String,
        baseUrl: json['baseUrl'] as String,
        apiKeyEnvVar: json['apiKeyEnvVar'] as String,
        models: (json['models'] as List<dynamic>)
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

/// The four providers the user is currently using, seeded with the
/// specific models visible in freellm.net's "Best Free Models by
/// Provider" table for each. The NVIDIA entry includes z-ai/glm-5.2
/// with supportsThinking: true, matching the snippet the user pasted
/// (extra_body.chat_template_kwargs.enable_thinking).
///
/// Deliberately NOT included: the freellm.net "Claude Code" config
/// snippet, which routes ANTHROPIC_BASE_URL through openrouter.ai.
/// That's a different product (Claude Code's own model backend, not a
/// model this app calls) and piping Anthropic auth through a
/// third-party relay isn't something to wire up by default - if the
/// user wants OpenRouter as a provider *for this app's chat feature*
/// (i.e. as another OpenAI-compatible /chat/completions backend, not as
/// Claude Code's transport), they can add it manually below.
final List<AiProvider> builtInProviders = [
  AiProvider(
    id: 'groq',
    name: 'Groq',
    baseUrl: 'https://api.groq.com/openai/v1/chat/completions',
    apiKeyEnvVar: 'GROQ_API_KEY',
    isBuiltIn: true,
    models: const [
      AiModel(id: 'llama-3.3-70b-versatile', label: 'Llama 3.3 70B'),
      AiModel(
        id: 'moonshotai/kimi-k2-instruct',
        label: 'Moonshot Kimi K2',
      ),
      AiModel(
        id: 'moonshotai/kimi-k2-instruct-0905',
        label: 'Moonshot Kimi K2 0905',
      ),
      AiModel(
        id: 'meta-llama/llama-4-scout-17b-16e-instruct',
        label: 'Llama 4 Scout 17B',
      ),
    ],
  ),
  AiProvider(
    id: 'modelscope',
    name: 'ModelScope',
    baseUrl: 'https://api-inference.modelscope.cn/v1/chat/completions',
    apiKeyEnvVar: 'MODELSCOPE_API_KEY',
    isBuiltIn: true,
    models: const [
      AiModel(
        id: 'MiniMax/MiniMax-M2.5',
        label: 'MiniMax M2.5 (highspeed)',
      ),
      AiModel(
        id: 'qwen-qwen3-5-35b-a3b',
        label: 'Qwen3.5 35B A3B',
      ),
      AiModel(
        id: 'qwen-qwen3-5-27b',
        label: 'Qwen3.5 27B',
      ),
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
      AiModel(
        id: 'z-ai/glm-5.1',
        label: 'Z-AI GLM 5.1',
      ),
      AiModel(
        id: 'poolside/laguna-xs-2.1',
        label: 'Poolside Laguna XS 2.1',
      ),
    ],
  ),
];